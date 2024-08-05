public with sharing class OpportunityTriggerHandler extends TriggerHandler {

    public override void beforeInsert() {
        for (Opportunity opp : (List<Opportunity>) Trigger.new){
            if (opp.Type == null){
                opp.Type = 'New Customer';
            }    
        }   
    }

    public override void beforeUpdate() {
        for (Opportunity opp : (List<Opportunity>) Trigger.new){
            if (opp.StageName != null){
                opp.Description += '\n Stage Change:' + opp.StageName + ':' + DateTime.now().format();
            }              
        }

        for(Opportunity opp : (List<Opportunity>) Trigger.new){
            if(opp.Amount < 5000){
                opp.addError('Opportunity amount must be greater than 5000');
            }
        }

        //Get contacts related to the opportunity account
        Set<Id> accountIds = new Set<Id>();
        for(Opportunity opp : (List<Opportunity>) Trigger.new){
            accountIds.add(opp.AccountId);
        }
        
        Map<Id, Contact> contacts = new Map<Id, Contact>([SELECT Id, FirstName, AccountId FROM Contact WHERE AccountId IN :accountIds AND Title = 'CEO' ORDER BY FirstName ASC]);
        Map<Id, Contact> accountIdToContact = new Map<Id, Contact>();

        for (Contact cont : contacts.values()) {
            if (!accountIdToContact.containsKey(cont.AccountId)) {
                accountIdToContact.put(cont.AccountId, cont);
            }
        }

        for(Opportunity opp : (List<Opportunity>) Trigger.new){
            if(opp.Primary_Contact__c == null){
                if (accountIdToContact.containsKey(opp.AccountId)){
                    opp.Primary_Contact__c = accountIdToContact.get(opp.AccountId).Id;
                }
            }
        }
    }

    public override void beforeDelete() {
        for (Opportunity oldOpp : (List<Opportunity>) Trigger.old){
            if (oldOpp.IsClosed){
                oldOpp.addError('Cannot delete closed opportunity');
            }
        }
        
        //Account related to the opportunities 
        Map<Id, Account> accounts = new Map<Id, Account>([SELECT Id, Industry FROM Account WHERE Id IN (SELECT AccountId FROM Opportunity WHERE Id IN :Trigger.old)]);
        for(Opportunity opp : (List<Opportunity>) Trigger.old){
            if(opp.StageName == 'Closed Won'){
                if(accounts.get(opp.AccountId).Industry == 'Banking'){
                    opp.addError('Cannot delete a closed won opportunity for a banking account');
                }
            }
        }
    }

    public override void afterInsert() {
        // Create a new Task for newly inserted Opportunities
        List<Task> listOfTasks = new List<Task>();
        for (Opportunity opp : (List<Opportunity>) Trigger.new){
            Task tsk = new Task();
            tsk.Subject = 'Call Primary Contact';
            tsk.WhatId = opp.Id;
            tsk.WhoId = opp.Primary_Contact__c;
            tsk.OwnerId = opp.OwnerId;
            tsk.ActivityDate = Date.today().addDays(3);
            listOfTasks.add(tsk);
        }
        insert listOfTasks;
    }

    public override void afterDelete() {
        notifyOwnersOpportunityDeleted(Trigger.old);
    }

    public override void afterUndelete() {
        assignPrimaryContact((Map<Id, Opportunity>) Trigger.newMap);
    }

    /*
    notifyOwnersOpportunityDeleted:
    - Sends an email notification to the owner of the Opportunity when it gets deleted.
    - Uses Salesforce's Messaging.SingleEmailMessage to send the email.
    */
    private static void notifyOwnersOpportunityDeleted(List<Opportunity> opps) {
        List<Messaging.SingleEmailMessage> mails = new List<Messaging.SingleEmailMessage>();
        Set<Id> oppOwnerIds = new Set<Id>();
        for (Opportunity opp : opps){
            oppOwnerIds.add(opp.OwnerId);
        }
        String[] toAddresses = new String[] {[SELECT Id, Email FROM User WHERE Id IN :oppOwnerIds].Email};
        for (Opportunity opp : opps){
            Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
            mail.setToAddresses(toAddresses);
            mail.setSubject('Opportunity Deleted : ' + opp.Name);
            mail.setPlainTextBody('Your Opportunity: ' + opp.Name +' has been deleted.');
            mails.add(mail);
        }        
        
        try {
            Messaging.sendEmail(mails);
        } catch (Exception e){
            System.debug('Exception: ' + e.getMessage());
        }
    }

    /*
    assignPrimaryContact:
    - Assigns a primary contact with the title of 'VP Sales' to undeleted Opportunities.
    - Only updates the Opportunities that don't already have a primary contact.
    */
    private static void assignPrimaryContact(Map<Id,Opportunity> oppNewMap) {        
        Map<Id, Opportunity> oppMap = new Map<Id, Opportunity>();
        Set<Id> oppAccountIds = new Set<Id>();
        for (Opportunity opp : oppNewMap.values()) {
            if (opp.AccountId != null) {
                oppAccountIds.add(opp.AccountId);
            }
        }

        Map<Id, Contact> accountByContactMap = new Map<Id, Contact>();
        for (Account acc : [
            SELECT Id, (SELECT Id, AccountId FROM Contacts WHERE Title = 'VP Sales' LIMIT 1)
            FROM Account
            WHERE Id IN :oppAccountIds
        ]) {
            if (!acc.Contacts.isEmpty()) {
                accountByContactMap.put(acc.Id, acc.Contacts[0]);
            }
        }

        for (Opportunity opp : oppNewMap.values()){            
            Contact primaryContact = accountByContactMap.get(opp.AccountId);
            if (primaryContact != null && opp.Primary_Contact__c == null){
                Opportunity oppToUpdate = new Opportunity(Id = opp.Id);
                oppToUpdate.Primary_Contact__c = primaryContact.Id;
                oppMap.put(opp.Id, oppToUpdate);
            }
        }
        update oppMap.values();
    }
}