---
layout: default
title: Setting Up Microsoft Foundry
---

# Microsoft Foundry Setup
This step will be completed in the workshop.

## Learning (Not Required)

* [Training for Microsoft Foundry: Microsoft Learn](https://learn.microsoft.com/en-us/training/azure/ai-foundry)
* [Quick Start for Microsoft Foundry: Microsoft Learn](https://learn.microsoft.com/en-us/azure/foundry/tutorials/quickstart-create-foundry-resources?tabs=portal)


## Authenication setup
To connect resources you will need one of two methods. Below describes how to set up these two methods. Key Authenication is the default and configured though the deployment script

1. One of two of the following security settings (Configured by running the baseline deployment)
    1. For using API Keys
        * The Azure AI Search Resource needs to have API Keys turned on (Search Service Resource --> Keys --> API Access control, select API keys or Both)
        * The Storage Account needs to have API Keys Active (Storage Account Resource --> Settings --> Allow storage account key access, Enabled)
        * The Foundry Hub Needs API keys enabled (Foundry Resource --> Properties --> Allow API key based authentication, Enabled)
    1. For Managed Identity Access 
        * Foundry Hub Identity needs the following roles (For simplicity set to resource group)
            * Cognitive Services User
            * Search Index Data Contributor
            * Storage Blob Data Reader
        * The Search Service Identity needs the following roles (For simplicity set to resource group)
            * Cognitive Services User
            * Storage Blob Data Reader

## Setting Up Microsoft Foundry

This guide walks you through setting up Microsoft Foundry in a way that complies with PNNL Birthright Subscription requirements.

### Navigate to the Resource Group
1. Open the Azure portal at <https://portal.azure.com>.
1. Sign in with the account you will use for the workshop.
1. Navigate to your subscription and the associated resource group created in the previous step.
1. You should see a screen similar to the one shown below.

![Resource Group Done](prettypictures/01-foundry.png)

### Find the Microsoft Foundry Resource in the Microsoft Azure Marketplace

1. Click the Create button above Essentials.

![Create Button](prettypictures/02-foundry.png)

2. In the upper `Search the Marketplace` search bar, search for `Foundry` and select the `Azure Services Only` checkbox.

![Azure Marketplace Search](prettypictures/03-foundry.png)

3. Click the Microsoft Foundry tile.

![Azure Marketplace Foundry Tile](prettypictures/04-foundry.png)

4. If you already clicked Create on the tile, you can skip this step. Otherwise, click Create on the following screen.

![Azure Create Foundry Page](prettypictures/05-foundry.png)

### Configure AI Foundry Deployment

#### Basics Page
1. On the Basics tab:
    1. verify the following and change if wrong
        * Subscription 
        * Resource Group
    1. Enter the following:
        * Name: a globally unique name that you choose like aifoundry-cortana
        * Region: one of the following
            - West US (Recommended)
            - West US 3
            - US South Central US
        * Foundry Project Name: For Example proj-cortana

![Basics Page](prettypictures/06-foundry.png)

2. Click Next at the bottom.

#### Storage
1. Accept the defaults and click Next at the bottom of the screen.

![Storage Page](prettypictures/07-foundry.png)

#### Inbound Networking
1. Accept the defaults and click Next at the bottom of the screen.

> `All networks, including the internet, can access this resource.` should be selected.

![Inbound Networking Page](prettypictures/08-foundry.png)

#### Outbound Networking
1. Accept the defaults and click Next at the bottom of the screen.

> `No Outbound Networking` should be selected.

![Outbound Networking Page](prettypictures/09-foundry.png)

#### Identity
1. Accept the defaults and click Next at the bottom of the screen.

> `System Assigned` should be selected.

![Identity Page](prettypictures/10-foundry.png)

#### Encryption
1. Accept the defaults and click Next at the bottom of the screen.

> Do **NOT** check the box for customer managed keys

![Encryption Page](prettypictures/11-foundry.png)

#### Tags
1. Accept the defaults and click Next at the bottom of the screen.

> Tags are not required

![Tags Page](prettypictures/12-foundry.png)

#### Review + Create
1. The system will automatically run validation on your selection.
1. Verify the settings on the Basics tab.
1. Click Create at the bottom.

## Verify Deployment

![Review and Create Page](prettypictures/13-foundry.png)

The deployment page will appear.

![Review and Create Page](prettypictures/14-foundry.png)

When the deployment is complete, it will look like the following. Click the Resource Group link to return to your resource group.

![Review and Create Page](prettypictures/15-foundry.png)

## Microsoft Foundry and Creating Deployments

### Log into Microsoft Foundry
There are two ways to log in to Microsoft Foundry:
1. Go to <ai.azure.com> Login and select the Azure Foundry Project that you created.
2. Click the link in the Foundry Project resource from your resource group.

![Open Foundry Page](prettypictures/16-foundry.png)

**If you do not see the new Foundry experience when you log in with the project name you created, stop and ask for help.**

![Open Foundry Page](prettypictures/17-foundry.png)
 
### Deploy Base Models

There are two models that you will deploy.

* We recommend the following models
    * gpt-4.1
    * text-embedding-3-small

> Any model that supports query planning and embeddings can be used. For more information, see [Which LLM models are supported for query planning?](https://learn.microsoft.com/en-us/azure/foundry/agents/concepts/foundry-iq-faq#which-llm-models-are-supported-for-query-planning).

1. Click Build.
2. Click Deployments.
3. Click Deploy Base Model.

![Operate Page](prettypictures/18-foundry.png)

4. Find the model to deploy. We recommend `gpt-4.1` or `text-embedding-3-small`.

![Open Foundry Page](prettypictures/19-foundry.png)

5. Click the model and select `Deploy --> Custom Settings`.

![Model Page](prettypictures/20-foundry.png)

6. Select `Deployment Zone Standard` and click `Deploy`. Do **NOT** choose `Priority Processing` or change the tokens-per-minute rate limit at this time.

![Deploy Fly Out](prettypictures/21-foundry.png)

Repeat these steps so that you have two deployments: one GPT deployment and one embedding deployment.

![Deployments Page with Models](prettypictures/22-foundry.png)

### Connect Resources

1) From the home Page. Click on `Operate`

![Deployments Page with Models](prettypictures/23-foundry.png)

2) From the Operate Page Click on `Admin` then click on the Foundry Hub name under the `Parent Resource` column (not the project name)

![Deployments Page with Models](prettypictures/24-foundry.png)

3) Click on `Connected Resources`
> If you see a API Key authentication is disabled you must use System Identity authencation. 

![Deployments Page with Models](prettypictures/25-foundry.png)

4) Click on `Add Connection`

![Deployments Page with Models](prettypictures/25-foundry.png)

5) Select `Azure AI Search` and `Continue`

![Deployments Page with Models](prettypictures/26-foundry.png)

6) Select the `Connect Manually`

From the Portal you can get the following information 
   1. Endpoint (On the Search Service `Overview` Screen it is under the `Essensials` labled `URL`)
   1. API Key  (On the Search Service `Keys` Screen use one of the admin keys)
   1. Give it a name such as `SearchServiceKB`
   1. Click `Connect`

![Deployments Page with Models](prettypictures/27-foundry.png)

7) Click on `Add Connection` again and select `Application Insights` and then `Continue`

![Deployments Page with Models](prettypictures/28-foundry.png)

8) Select the `Application Insights` that was created with the script. 

![Deployments Page with Models](prettypictures/29-foundry.png)

9) You should now have 2 new Connected Resources

![Deployments Page with Models](prettypictures/30-foundry.png)


