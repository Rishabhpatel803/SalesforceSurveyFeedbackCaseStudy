# Salesforce Surveys & Customer Feedback Management System

> End-to-End Salesforce Solution for Automated Customer Feedback Collection, CSAT & NPS Measurement, Case Escalation, and Analytics.

![Salesforce](https://img.shields.io/badge/Salesforce-Sales%20Cloud-blue)
![Platform](https://img.shields.io/badge/Platform-Salesforce%20Surveys-green)
![Automation](https://img.shields.io/badge/Automation-Flows%20%26%20Apex-orange)
![Status](https://img.shields.io/badge/Status-Implementation%20Ready-success)

---

# Overview

The **Salesforce Surveys & Customer Feedback Management System** automates the complete customer feedback lifecycle for **ExploreConnect Travels**.

Whenever a customer completes a travel booking, Salesforce automatically:

- Sends a Survey Invitation
- Collects customer feedback
- Calculates CSAT & NPS
- Updates booking and package metrics
- Escalates poor feedback to Customer Support
- Provides dashboards and reports for management

The solution leverages **Sales Cloud**, **Salesforce Surveys**, **Flow Automation**, **Apex**, and **Reports & Dashboards** to provide a fully automated customer feedback management platform.

---

# Business Problem

ExploreConnect Travels collected customer feedback manually, leading to:

- Inconsistent feedback collection
- Low survey completion rates
- Delayed response to dissatisfied customers
- No centralized reporting
- No customer satisfaction metrics
- Manual follow-up process

---

# Solution

This solution automates the complete customer feedback lifecycle.

```
Trip Completed
        │
        ▼
Survey Invitation
        │
        ▼
Customer Completes Survey
        │
        ▼
CSAT & NPS Calculation
        │
        ▼
Negative Feedback?
   │             │
  No            Yes
   │             │
   ▼             ▼
Dashboard    Create Case
                │
                ▼
         Customer Support
```

---

# Solution Architecture

```
Customer
    │
    ▼
Sales Cloud
(Travel Booking)

    │

Automation Layer
(Flows)

    │

Salesforce Surveys

    │

Business Logic
(Apex)

    │

Analytics + Service Cloud
```

---

# Key Features

## Automated Survey Invitation

- Survey automatically sent when booking status becomes **Completed**
- Uses Salesforce Surveys
- Sends invitation email automatically

---

## Customer Feedback Collection

Captures:

- Overall Experience
- Guide Rating
- Hotel Rating
- Transportation Rating
- Recommendation Score (NPS)
- Comments
- Photo Upload

---

## Automatic Rating Calculation

Automatically calculates:

- Average Rating
- CSAT
- Net Promoter Score (NPS)

---

## Automatic Case Creation

If

```
Average Rating < 3
```

then Salesforce automatically:

- Creates High Priority Case
- Assigns Support Queue
- Sends Internal Notification

---

## Reminder Automation

Daily scheduled automation checks:

- Survey Sent
- Not Completed
- More than 5 Days

Automatically:

- Sends Reminder Email
- Creates Follow-up Task

---

## Analytics Dashboard

Provides:

- Survey Completion Rate
- Destination Performance
- Guide Performance
- NPS Trend
- Escalated Cases
- Customer Satisfaction

---

# Technology Stack

| Component | Technology |
|------------|------------|
| CRM | Salesforce Sales Cloud |
| Surveys | Salesforce Surveys |
| Automation | Record Triggered Flow |
| Automation | Scheduled Flow |
| Business Logic | Apex |
| Batch Processing | Batch Apex |
| Reporting | Salesforce Reports |
| Dashboard | Salesforce Dashboard |

---

# Salesforce Objects

## Custom Objects

- Travel_Booking__c
- Tour_Package__c

## Standard Objects

- Contact
- Opportunity
- Survey
- Survey Invitation
- Survey Response
- Case
- Task
- EmailMessage

---

# Automation Components

## Flow 1

Booking Completed

Responsible for:

- Create Survey Invitation
- Send Email
- Update Booking

---

## Flow 2

Survey Submitted

Responsible for:

- Retrieve Booking
- Calculate Ratings
- Update Booking
- Trigger Escalation

---

## Flow 3

Negative Feedback

Responsible for:

- Create Case
- Assign Queue
- Notify Support

---

## Scheduled Flow

Responsible for:

- Survey Reminder
- Follow-up Task

---

# Apex Components

## SurveyRatingCalculator

Responsibilities

- Calculate Average Rating
- Calculate NPS
- Update Booking
- Update Package Metrics
- Bulk Processing

---

## NightlySurveyAggregationBatch

Responsibilities

- Aggregate Ratings
- Calculate Package NPS
- Reconciliation
- Email Summary

---

# Reporting

The solution includes:

- Survey Completion Report
- Destination Performance
- Guide Performance
- Escalated Cases
- NPS Trend
- Customer Feedback Dashboard

---

# Security

- Field Level Security
- Queue Based Case Assignment
- Salesforce Survey Guest Access
- Read-only Metrics
- Flow Fault Handling

---

# Project Structure

```
Salesforce-Surveys/
│
├── Apex
│   ├── SurveyRatingCalculator.cls
│   ├── NightlySurveyAggregationBatch.cls
│
├── Flows
│   ├── BookingCompletion.flow
│   ├── SurveyResponse.flow
│   ├── NegativeFeedback.flow
│   ├── ReminderScheduler.flow
│
├── Objects
│   ├── Travel_Booking__c
│   ├── Tour_Package__c
│
├── Reports
│
├── Dashboard
│
├── Documentation
│
└── README.md
```

---

# High-Level Process Flow

```
Travel Booking Completed
            │
            ▼
Generate Survey Invitation
            │
            ▼
Send Email
            │
            ▼
Customer Completes Survey
            │
            ▼
Calculate Rating & NPS
            │
     ┌──────┴───────┐
     │              │
Positive      Negative
     │              │
     ▼              ▼
Dashboard     Create Case
                   │
                   ▼
            Customer Support
```

---

# Benefits

- 100% Automated Survey Distribution
- Faster Customer Feedback Collection
- Automated Customer Satisfaction Tracking
- Automatic Service Recovery
- Reduced Manual Effort
- Improved Customer Experience
- Real-time Dashboards
- Scalable Architecture
- Enterprise Ready

---

# Future Enhancements

- Multi-language Surveys
- SMS Survey Invitations
- WhatsApp Integration
- Einstein Sentiment Analysis
- Experience Cloud Portal
- AI-based Recommendation Engine
- Slack Notifications
- Agentforce Integration

---

# Author

**Rishabh Patel**

Salesforce Developer

---

## License

This project is intended for educational, portfolio, and solution architecture demonstration purposes.