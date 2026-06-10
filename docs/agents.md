# Agents Workshop

> Note If you would like to use the Knowledge base created in Workshop 1 for your agents remove the CSV files from the knowledge base as in this exercise we will use these files differently. Workshop 1 on Knowledge Bases is not a prereq to this workshop.

Microsoft Foundry helps you turn AI ideas into reliable workflows by combining models, tools, and data through Agents. In this workshop, you will learn how an Agent is designed with clear instructions, connected resources, and task-specific behavior so it can complete meaningful work, not just answer prompts. You will also explore the Agent workflow, which breaks a request into steps such as planning, tool use, validation, and response generation. This workflow makes outcomes more consistent, easier to troubleshoot, and safer to run in real scenarios. As you build, you will see how context, memory, and external data sources improve the quality and relevance of results. You will also practice evaluating Agent outputs and refining prompts, policies, and tool connections to improve performance over time. By the end, you should understand how to move from a simple conversational Agent to a structured, production-ready workflow in Foundry.

## Prereq
1. [Hack Baseline Deployment](index.html)
1. [Microsoft Foundry Model Deployment](foundry.html)
1. Download the cvs files click the 
![Download Image](./prettypictures/agent-02.png)
    * [Generic Mental Health Dataset](https://github.com/Patrick-Davis-MSFT/hack-baseline-setup/blob/main/data/Coffee/CoffeeCSV/GeneralHealth/synthetic_mental_health_dataset.csv)
    * [Large Mental Health Dataset](https://github.com/Patrick-Davis-MSFT/hack-baseline-setup/blob/main/data/Coffee/CoffeeCSV/mentalHealth/synthetic_coffee_health_10000.csv)


To use Knowledge Bases the following needs to be in place to create the knowledge base
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


## Create a Statistical Agent

1. In the [Azure Portal](https://portal.azure.com) Go to your Microsoft Foundry Project Resource created in the previous step. Click on `Go to Foundry Portal`.

![Find Foundry Project in Portal](./prettypictures/kb-01.pnb)

2. From the Foundry Project Home Page Click on `Build`

![Foundry Project Home Page](./prettypictures/kb-02.png)

3. From the Agents Page select `New agent`. Select `Build a agent` and give the agent a name like `stats-for-coffee` click create

![Foundry Project Home Page](./prettypictures/agent-01.png)

4. On the Playground Form 
    * Model: The model created previously
    * Instructions: Copy and Paste from below
    * Remove the Web Search under Tools
    * Add the Code interpreter under Tools
    * Click `+ Files` Under the Code interpreter and Upload the CSVs that you downloaded earlier. Click Attach. When they get first uploaded they will appear as `assistant-[unique string]`. This is expected. The file names will show after refreshing the screen. 
    * Save the Agent

Instructions
```text
You are a rigorous data-analysis agent for a scientific workshop in Microsoft Foundry.

  Primary mission:
  - Analyze two workshop CSV files using Code Interpreter.
  - Explain findings in plain English and show the exact calculation logic.
  - Generate charts when they help understanding.
  - Be explicit about uncertainty, synthetic-data limitations, and non-causal interpretations.

  Available datasets:
  1) synthetic_mental_health_dataset.csv
     Typical columns include: Timestamp, Gender, Country, Occupation, self_employed,
     family_history, treatment, Days_Indoors, Growing_Stress, Changes_Habits,
     Mental_Health_History, Mood_Swings, Coping_Struggles, Work_Interest,
     Social_Weakness, mental_health_interview, care_options.

  2) synthetic_coffee_health_10000.csv
     Typical columns include: ID, Age, Gender, Country, Coffee_Intake, Caffeine_mg,
     Sleep_Hours, Sleep_Quality, BMI, Heart_Rate, Stress_Level,
     Physical_Activity_Hours, Health_Issues, Occupation, Smoking,
     Alcohol_Consumption.

  Behavioral rules:
  - Always inspect schema first before calculating.
  - Use Python for any numeric, statistical, plotting, grouping, filtering, or transformation task.
  - Prefer reproducible steps: summarize -> clean -> analyze -> visualize -> interpret.
  - When comparing variables, report the exact method used (for example: Pearson correlation,
    grouped mean, contingency table, simple regression).
  - Do not claim causation from correlation.
  - If the user asks to compare the two datasets, do NOT fabricate a row-level join unless there is
    a shared key. Instead, perform thematic comparison across similarly named concepts (for example:
    stress, sleep, occupation, country, gender).
  - When generating a file, save charts as PNG and tabular outputs as CSV when practical.

  Preferred output format:
  1. Question being answered
  2. Datasets and columns used
  3. Method
  4. Results
  5. Interpretation
  6. Caveats
```

[Playground Setting](./prettypictures/agent-03.png)

## Have a conversation with the Agent 

Enter these five prompts (Or your own in order)

* Start by inspecting both datasets and give me a schema report: column names, data types, missing values, duplicates, and any obvious data quality issues. Then propose a clean analysis plan.
* Analyze how coffee intake relates to stress level, sleep hours, sleep quality, heart rate, and BMI. Use appropriate statistics and charts, show exact calculation steps, and clearly separate correlation from causation.
* Build a country- and gender-level comparison dashboard summary across both datasets for stress-related indicators. Show grouped tables, at least 3 visualizations, and highlight the top 5 notable patterns.
* Compare occupation patterns across the two datasets. Identify which occupations appear most associated with higher stress signals, explain the method (grouped means or contingency analysis), and include caveats.
* Create a reproducible mini-report with: question, datasets/columns used, method, results, interpretation, and caveats. Export key result tables as CSV and charts as PNG files I can download.

## Optional Add The Knowledge Base 

> Remove the CSV datasource so that datasources are not duplicated. 

1. Under Knowlege add the Knowledge base created in Workshop 1
1. Converse with the Agent using the following prompts

## 3-Turn Script (Code Interpreter + Knowledge Base)

Try this script with the both the Code interpeter and the Knowledge base

### Turn 1
Start a combined analysis using both uploaded CSV files and the connected knowledge base.

Assume the CSV records are de-identified study data (not synthetic), and treat them as observational evidence with appropriate limitations.

First:
1. Inspect schema, data quality, missingness, and outliers.
2. Identify comparable variables across datasets.
3. Provide a brief analysis plan for sleep, stress, and cardiovascular indicators.

### Turn 2
Run quantitative analysis in Code Interpreter, then ground findings with the knowledge base.

In Code Interpreter:
1. Quantify associations between coffee exposure (Coffee_Intake, Caffeine_mg) and outcomes (Sleep_Hours, Sleep_Quality, Stress_Level, Heart_Rate, BMI).
2. Include subgroup comparisons by Gender and Country.
3. Show methods, effect sizes, uncertainty, and 2-3 charts.

In Knowledge Base:
1. Retrieve at least 2 relevant studies or reviews for each major claim area (sleep/stress and cardiovascular).
2. Compare whether external evidence supports, contradicts, or is mixed relative to dataset findings.

### Turn 3
Create a final evidence synthesis with this exact structure:

1. Direct answer (3-5 sentences)
2. Data analysis results (with key numbers)
3. Evidence from knowledge base (with citations)
4. Agreement vs conflict between dataset findings and literature
5. Confidence rating (High/Moderate/Low) with reason
6. Limitations (observational design, confounding, generalizability)
7. Next analyses to strengthen conclusions

Also export charts as PNG and summary tables as CSV.

## Up Next: Multi Agents
[Multi Agent Workflows](multi-agent.html)
