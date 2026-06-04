---
layout: default
title: Setting Up Microsoft Foundry
---

# Microsoft Foundry Setup

## Learning Not Required

* [Training for Microsoft Foundry: Microsoft Learn](https://learn.microsoft.com/en-us/training/azure/ai-foundry)
* [Quick Start for Microsoft Foundry: Microsoft Learn](https://learn.microsoft.com/en-us/azure/foundry/tutorials/quickstart-create-foundry-resources?tabs=portal)

## Setting Up Microsoft Foundry

This guide will walk you though setting up the Microsoft Foundry compliant to PNNL Birthright Subscription Requirements

### Navigate to the Resource Group
1. Open the Azure portal at <https://portal.azure.com>.
1. Sign in with the account you will use for the workshop.
1. Navigate to your Subscription and the Associated Resource Group created in the previous Step. 
1. You should see a screen simular to the following below

![Resource Group Done](prettypictures/01-foundry.png)

### Find the Microsoft Foundry Resource in the Microsoft Azure Marketplace

1. Click The Create button above essentials

![Create Button](prettypictures/02-foundry.png)

2. In the upper `Search the Marketplace` searchbar for `Foundry` and select the `Azure Services Only` Checkbox

![Azure Marketplace Search](prettypictures/03-foundry.png)

3. Click The Microsoft Foundry Tile

![Azure Marketplace Foundry Tile](prettypictures/04-foundry.png)

4. If you did not click Create on the tile click create on the following page

![Azure Create Foundry Page](prettypictures/05-foundry.png)

### Configure AI Foundry Deployment

#### Basics Page
1. On the Basics Tab 
    1. verify the following and change if wrong
        * Subscription 
        * Resource Group
    1. Add Enter the following
        * Name: a globally unique name that you choose like aifoundry-cortana
        * Region: one of the following
            - West US (Recommended)
            - West US 3
            - US South Central US
        * Foundry Project Name: For Example proj-cortana

![Basics Page](prettypictures/06-foundry.png)

2. Click Next At the bottom

#### Storage
1. Accept the defaults and click Next at the bottom of the screen

![Storage Page](prettypictures/07-foundry.png)

#### Inbound Networking
1. Accept the defaults and click Next at the bottom of the screen

> `All networks, including the internet, can access this resource.` Should be selected.

![Inbound Networking Page](prettypictures/08-foundry.png)

#### Outbound Networking
1. Accept the defaults and click Next at the bottom of the screen

> `No Outbound Networking` Should be selected.

![Outbound Networking Page](prettypictures/09-foundry.png)

#### Identity
1. Accept the defaults and click Next at the bottom of the screen

> `System Assigned` Should be selected.

![Identity Page](prettypictures/10-foundry.png)

#### Encryption
1. Accept the defaults and click Next at the bottom of the screen

> Do **NOT** check the box for customer managed keys

![Encryption Page](prettypictures/11-foundry.png)

#### Tags
1. Accept the defaults and click Next at the bottom of the screen

> Tags are not required

![Tags Page](prettypictures/12-foundry.png)

#### Review + Create
1. The system will automatically run validation on your selection. 
1. Verify the Basics settings
1. Click Create at the bottom 

## Verify Deployment

![Review and Create Page](prettypictures/13-foundry.png)

The deployment page will appear 

![Review and Create Page](prettypictures/14-foundry.png)

When Complete it will look like the following. Click the Resource Group link to return to your Resource Group

![Review and Create Page](prettypictures/15-foundry.png)

## Microsoft Foundry and Creating Deployments

### Log into Microsoft Foundry
There are two ways to log into Microsoft Foundry 
1. Go to <ai.azure.com> Login and select the Azure Foundry Project that you created.
2. Click on the link in the Foundry Project resource from your resource group

![Open Foundry Page](prettypictures/16-foundry.png)

**If you do not see the New Foundry on Login with your Project Name that you created STOP and Ask for Help**

![Open Foundry Page](prettypictures/17-foundry.png)
 
### Deploy Base Models

There will be two models we will deploy it 
* gpt-4.1
* text-embedding-3-small

1. Click On Build
2. Click On Deployments
3. Click On Deploy Base Model

![Operate Page](prettypictures/18-foundry.png)

4. Find the model to deploy (Recommended gpt-4.1 or text-embedding-3-small)

![Open Foundry Page](prettypictures/19-foundry.png)

5. Click On the Model and select `Deploy --> Custom Settings`

![Model Page](prettypictures/20-foundry.png)

6. Select `Deployment Zone Standard` and click `Deploy`. Do **NOT** choose `Priority Processing` OR Change the Tokens Per Minute Rate Limit at this time

![Deploy Fly Out](prettypictures/21-foundry.png)

Repeat these steps so that you will have two deployments, a GPT deployment and an Embedding Deployment

![Deployments Page with Models](prettypictures/22-foundry.png)