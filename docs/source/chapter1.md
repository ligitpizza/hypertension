Chapter 1

**Introduction**

**Table of Contents**

[**1.1 Introduction**](#) **2**

[**1.2 Project Background**](#project-background) **3**

[**1.3 Problem Statement**](#problem-statement) **5**

[**1.4 Solutions**](#solutions) **8**

> [1.4.1 Solution to Problem 1: Lack of Continuous Monitoring](#solution-to-problem-1-lack-of-continuous-monitoring) 8
>
> [1.4.2 Solution to Problem 2: Poor Medication Adherence](#solution-to-problem-2-poor-medication-adherence) 9
>
> [1.4.3 Solution to Problem 3: Fragmented Care Coordination](#solution-to-problem-3-fragmented-care-coordination) 9

[**1.5 Project Objectives**](#) **11**

[**1.6 Project Scope**](#project-scope) **13**

[**1.7 Existing or Similar Systems**](#existing-or-similar-systems) **15**

> [1.7.1 Omron Connect](#omron-connect) 15
>
> [1.7.2 Withings Health Mate](#withings-health-mate) 15
>
> [1.7.3 Feature Comparison](#feature-comparison) 16

[**1.8 Advantages and Contribution**](#) **17**

> [1.8.1 Advantages](#) 18
>
> [1.8.2 Limitations](#) 20
>
> [1.8.3 Sustainability Contribution (SDG Alignment)](#sustainability-contribution-sdg-alignment) 21

[**1.9 System Development Methodology and Project Plan**](#) **22**

> [1.9.1 Methodology](#) 22
>
> [1.9.2 Development Phases](#development-phases) 23
>
> [1.9.3 Project Schedule](#project-schedule) 25
>
> [1.9.3.1 Project Schedule (Gantt Chart)](#project-schedule-gantt-chart) 25

[**1.10 Project Team and Organisation**](#) **26**

> [1.10.1 Developer](#developer) 26
>
> [1.10.2 Organisation Chart](#organisation-chart) 27

[**1.11 Chapter Summary**](#) **28**

[**1.12 References**](#references) **30**

**1.1 Introduction**

Hypertension, or high blood pressure, is one of the most prevalent and dangerous chronic diseases affecting populations worldwide. It is a leading risk factor for cardiovascular disease, stroke, kidney failure, and premature death, yet it is largely silent patients can live with dangerously elevated readings without any noticeable symptoms. The World Health Organization (WHO) estimates that 1.28 billion adults worldwide are currently living with hypertension, with nearly half unaware of their condition (WHO, 2023). In Malaysia, the National Health and Morbidity Survey (NHMS) 2023 recorded hypertension prevalence at 29.2%, representing approximately 6.7 million adults, with 11.9% remaining undiagnosed (Institute for Public Health, 2024). The disease burden has grown consistently over decades, with prevalence recorded at 32.9% in 1996, 34.6% in 2006, and 35.3% in 2015, establishing hypertension as a leading contributor to cardiovascular morbidity and premature death in Malaysia (Ab Majid et al., 2018).

Despite its severity, hypertension management remains reactive rather than proactive. Patients rely on infrequent clinic visits, struggle with medication adherence, and have limited tools to self-monitor and communicate meaningfully with their healthcare providers (Lobo et al., 2023). Anti-hypertensive medication non-adherence is estimated at 27%–40% globally, with up to 50% of patients discontinuing their prescribed medications within one year of initiation (Lee et al., 2022). At the same time, healthcare providers lack integrated digital platforms that bring together monitoring data, AI-powered risk intelligence, and care coordination in one place (Shahid et al., 2022).

This project proposes the Hypertension Care Management Platform, a Flutter-based mobile application designed for hypertension patients and healthcare providers within a private hospital setting in Malaysia. The platform integrates blood pressure tracking, AI-powered disease complication risk prediction using machine learning, medication management, secure patient-doctor messaging, symptom triage, and emergency family alerts into a single unified system enabling proactive hypertension management and reducing preventable complications. Research shows that mHealth app-based interventions have the potential to improve patient health knowledge and support self-management toward a healthier lifestyle, including medication adherence and physical activity, thereby achieving optimal blood pressure control (Liu et al., 2023).

# 1.2 Project Background

Hypertension is currently managed through a predominantly clinic-centric model in both Malaysia and globally. Under this model, patients attend scheduled consultations at periodic intervals, have their blood pressure measured during the visit, receive prescription adjustments if clinically indicated, and are discharged until the next appointment. While this approach is sufficient for stable, well-controlled patients, it is structurally inadequate for a condition as dynamic and often asymptomatic as hypertension (Lobo et al., 2023).

Blood pressure is not static. It fluctuates significantly throughout the day in response to physical activity, psychological stress, dietary sodium intake, sleep quality, and medication timing (WHO, 2023). A reading taken during a single clinic visit may not accurately represent a patient's true blood pressure profile and can mask periods of dangerous elevation that occur between appointments. This phenomenon commonly referred to in clinical literature as masked hypertension is a known risk factor for end-organ damage even in patients who appear well-controlled during consultations (Nakrys et al., 2023). Under the current model, these inter-visit elevations go entirely undetected. The National Health and Morbidity Survey of Malaysia reported that for every two persons diagnosed with hypertension, there are three persons with undiagnosed hypertension, a pattern that has remained unchanged since 2011, underscoring the scale of this monitoring gap (Ibrahim et al., 2022). There is a demonstrated lack of apps with a clinician portal to support remote patient management, and apps integrated with wearable devices for lifestyle interventions in people with hypertension with a clinician portal are not widely available (Lobo et al., 2023).

Medication management between visits is similarly unsupported. Once a patient leaves the clinic, there is no structured mechanism to remind them to take medications, track whether doses are missed, alert the care team when adherence deteriorates, or facilitate timely prescription refills (Wang et al., 2024). Anti-hypertensive medication non-adherence is the leading cause of poor blood pressure control and thereby cardiovascular diseases and mortality worldwide, recorded globally at 27%–40% in a meta-analysis of data from 2010 to 2020 involving 27 million patients (Lee et al., 2022). Up to 50% of patients stop taking their prescribed antihypertensive medications within one year of initiation (Lee et al., 2022).

The healthcare record landscape compounds these challenges. In Malaysia, there is no centralised national health record system. Private hospitals maintain their own siloed patient management systems that do not interoperate with each other or with the public sector (Tee et al., 2025). The digitalisation gap between the public and private sectors, if left unaddressed, may lead to a fragmented and inequitable healthcare landscape (Tee et al., 2025). Patients who receive care from multiple providers have no reliable way to consolidate or share their health history (Loo et al., 2023). Healthcare providers, in turn, must make clinical decisions with incomplete information, increasing the risk of errors and suboptimal management.

Finally, family members who play a critical role in patient care in the Malaysian cultural context are excluded from the current monitoring process. They receive no real-time visibility into a patient's health status and are only involved when a medical emergency has already occurred (WHO, 2023). This represents a missed opportunity, given that family involvement has been shown to improve medication adherence, appointment attendance, and chronic disease outcomes (Muehlensiepen et al., 2024).

The current process therefore suffers from three structural gaps: the absence of continuous between-visit monitoring, the lack of a structured adherence support system, and the fragmentation of communication and data across care stakeholders. These gaps collectively reduce the quality of hypertension management and increase the risk of preventable complications (Shahid et al., 2022). The Hypertension Care Management Platform is designed to address all three through an integrated, AI-powered mobile application built specifically for the Malaysian private hospital setting.

# 1.3 Problem Statement

Hypertension is a chronic condition that demands consistent, ongoing management, yet the systems currently available to patients and healthcare providers are structurally inadequate for this purpose. Three core problems drive the need for the Hypertension Care Management Platform.

**Problem 1: Lack of Continuous Monitoring**

Blood pressure is not static; it fluctuates significantly throughout the day in response to physical activity, psychological stress, dietary sodium intake, sleep quality, and medication timing (WHO, 2023). Dangerous elevations can occur silently between clinic visits without producing any noticeable symptoms, a phenomenon known as masked hypertension, which is a recognised risk factor for end-organ damage even in patients who appear well-controlled during consultations (Nakrys et al., 2023). Despite this, the prevailing model of hypertension management remains clinic-centric, with patients attending periodic appointments as their only structured point of monitoring contact.

The consequences of this monitoring gap are significant. The National Health and Morbidity Survey of Malaysia found that for every two persons diagnosed with hypertension, there are three persons with undiagnosed hypertension, a trend that has remained unchanged since 2011 (Ibrahim et al., 2022). Early warning signs are routinely missed because no mechanism exists to capture, analyse, or act on readings between appointments. A review of existing hypertension applications confirms that consumer-facing tools such as Omron Connect and Withings Health Mate address only basic data logging and visualisation. No widely available application provides a clinician portal to support remote patient monitoring, and apps integrated with wearable devices for lifestyle interventions in hypertension patients with a clinician portal are not widely available (Lobo et al., 2023). Without continuous, structured monitoring, clinical deterioration goes undetected until it manifests as a medical emergency.

**Problem 2: Poor Medication Adherence**

Anti-hypertensive medication non-adherence is the leading cause of poor blood pressure control and a primary contributor to cardiovascular disease and preventable mortality worldwide. A meta-analysis of data from 2010 to 2020 involving 27 million patients recorded global non-adherence rates of 27–40%, with up to 50% of patients discontinuing their prescribed antihypertensive medications within one year of initiation (Lee et al., 2022). In the current clinic-centric model, once a patient leaves the consultation room, no structured mechanism exists to remind them to take medications, track whether doses are missed, alert the care team when adherence deteriorates, or facilitate timely prescription refills (Wang et al., 2024).

This gap is consequential at both the individual and population level. At the individual level, each missed dose allows blood pressure to rise unchecked, accelerating the progression of hypertension-related complications including stroke, coronary artery disease, and chronic kidney disease. At the population level, the cumulative burden of non-adherence across millions of patients translates directly into higher rates of cardiovascular morbidity, avoidable hospitalisations, and premature death. Without a structured digital system for medication reminders, adherence logging, and automated refill workflows, missed doses go unrecorded and unaddressed, silently enabling the disease to progress between visits.

**Problem 3: Fragmented Care Coordination**

In Malaysia, there is no centralised national health record system. Private hospitals maintain their own siloed patient management systems that do not interoperate with each other or with the public sector (Tee et al., 2025). The digitalisation gap between the public and private sectors, if left unaddressed, may lead to a fragmented and inequitable healthcare landscape (Tee et al., 2025; Loo et al., 2023). Patients who receive care from multiple providers have no reliable way to consolidate or share their health history, while healthcare providers must make clinical decisions with incomplete information, increasing the risk of errors and suboptimal management.

Beyond the provider-to-provider coordination gap, patients, doctors, family members, and pharmacists currently operate across disconnected channels with no unified platform to support real-time communication, shared care planning, or coordinated clinical response.

Family members, who play a critical role in chronic disease management in the Malaysian cultural context, are entirely excluded from the current monitoring process and are typically involved only after a medical emergency has already occurred (WHO, 2023). Family involvement has been demonstrated to improve medication adherence, appointment attendance, and chronic disease outcomes (Muehlensiepen et al., 2024), yet no existing hypertension platform provides any mechanism to facilitate this involvement.

If these coordination failures remain unresolved, the consequence is a care environment in which clinical decisions are made with incomplete information, deteriorating patients go unnoticed until a crisis occurs, and the full potential of multi-stakeholder care is never realised. These three structural gaps insufficient continuous monitoring, inadequate adherence support, and fragmented care coordination collectively reduce the quality of hypertension management and increase the risk of preventable complications (Shahid et al., 2022). The Hypertension Care Management Platform is designed to address all three through a unified, AI-powered mobile application built specifically for the Malaysian private hospital setting.

#  

# 1.4 Solutions

The Hypertension Care Management Platform is a Flutter-based mobile application that addresses the three core problems of continuous monitoring absence, medication non-adherence, and fragmented care coordination through an integrated system of core technologies, modules, and features designed specifically for hypertension patients and healthcare providers within a Malaysian private hospital setting.

## 1.4.1 Solution to Problem 1: Lack of Continuous Monitoring

The platform addresses the absence of continuous monitoring through four integrated components. The primary input method is manual blood pressure logging, which enables patients to record readings at any time outside of clinic visits, providing a continuous stream of BP data that is not limited to scheduled appointments.

Heart rate is captured using Mobile Camera PPG, where patients place their finger over the smartphone camera. The camera captures RGB pixel intensity in real time, isolates the green channel as it is the most sensitive to blood flow changes, and applies a peak detection algorithm to calculate heart rate in beats per minute (Benezeth et al., 2023; Mather, 2024). This reading is automatically cross-referenced alongside blood pressure values within the triage engine and is activated each time the patient opens the Symptom Checker module.

Health Data Visualisation presents interactive blood pressure trend charts across 7-day, 30-day, 3-month, and 1-year views with statistical summaries, and tracks disease risk score trends over time, enabling both patients and healthcare providers to identify patterns and deterioration that would otherwise go undetected between clinic visits.

When readings exceed defined thresholds, the AI-Powered Health Monitoring module delivers real-time threshold alerts categorised as Mild, Moderate, or Emergency. The Symptom Checker and Triage engine extends this further by allowing patients to select from a structured list of hypertension-related symptoms and rate their severity. The triage engine cross-references all input symptoms, severity, current blood pressure, PPG-captured heart rate, and machine learning risk scores to produce a structured clinical outcome of either Monitor at Home, Contact Your Doctor, or Seek Emergency Care. Results are saved to the patient health record, and the assigned doctor is automatically notified for all Moderate and Emergency outcomes.

## 1.4.2 Solution to Problem 2: Poor Medication Adherence

The platform addresses medication non-adherence through the Medication Management module and the Recurring Medication, Payment, and Delivery module. The Medication Management module allows patients to add, edit, and delete medications with dosage schedules, receive push notification reminders, log missed doses, track their adherence rate, and receive refill and drug interaction alerts. These features provide the structured reminder and dose-logging system that is absent from the current clinic-centric model (Wang et al., 2024).

For long-term chronic patients, doctors can flag them for a recurring prescription workflow. The system automatically notifies patients monthly to confirm their order, processes payment via Stripe, and notifies the pharmacist to prepare the medication. Home delivery is dispatched through the Grab API with real-time doorstep tracking and push notifications sent at every delivery stage, with the cycle repeating automatically each month. This end-to-end recurring prescription workflow removes the logistical burden of manual refill management from both the patient and the care team, directly addressing the adherence gap caused by patients discontinuing medications or failing to collect refills (Lee et al., 2022).

## 1.4.3 Solution to Problem 3: Fragmented Care Coordination

The platform addresses fragmented care coordination through five integrated components. The Care Coordination and Messaging module provides secure end-to-end encrypted communication between patients and their assigned doctors, with shared care plan access across the full care team. An NLP Message Analysis scanner monitors all patient-doctor messages for high-risk keywords such as "chest pain" or "severe dizziness" and automatically escalates flagged messages as urgent to the assigned doctor, ensuring critical patient communications are never delayed or overlooked in a high-volume inbox (Mermin-Bunnell et al., 2023).

The Healthcare Provider Portal allows doctors to view and manage their assigned patient lists filtered by machine learning-predicted risk level, access full patient health histories, write clinical notes, issue prescriptions, and receive AI-prioritised risk alerts and 30-day deterioration notifications. This gives healthcare providers a consolidated, real-time view of their patient population that is not possible under the current siloed model (Lobo et al., 2023).

The Machine Learning Disease Risk Prediction engine, built on Random Forest and XGBoost algorithms (Wu et al., 2024), simultaneously predicts patient risk across five major hypertension-related complications Stroke, Coronary Artery Disease, Heart Failure, Chronic Kidney Disease, and Type 2 Diabetes drawing on twelve input variables. Risk is categorised as Low, Moderate, High, or Critical. When disease risk reaches a Critical threshold, emergency alerts are automatically sent to linked family members containing the patient's live GPS location, and full escalation protocols including emergency appointment booking and AI-guided patient instructions are activated.

The Family Monitoring and Emergency Alert feature allows linked family members to view the patient's real-time blood pressure readings and health status at any time, and to access a one-tap emergency call button when a Critical alert is triggered. The AI Health Agent, powered by Google Gemini Flash, provides patients with 24/7 context-aware guidance based on their live vitals, risk scores, medications, and medical history, and delivers proactive health status updates after each vital entry. Together, these components connect patients, healthcare providers, pharmacists, family members, and administrators within a single unified platform, closing the coordination gap that exists across the current fragmented care landscape.

#  

# 1.5 Project Objectives

The Hypertension Care Management Platform is guided by three primary objectives that define the functional scope of the system and serve as the measurable basis for evaluating its success upon completion. Each objective is formulated according to the SMART criteria Specific, Measurable, Achievable, Relevant, and Time-bound to ensure clarity and evaluability throughout the project lifecycle.

**Objective 1** To design and develop a Flutter-based hypertension patient monitoring system that enables patients to manually log blood pressure readings and capture heart rate via mobile camera PPG, visualise health trends through interactive charts across 7-day, 30-day, 3-month, and 1-year views, and receive automated threshold-based alerts categorised as Mild, Moderate, or Emergency to support timely clinical intervention. The system shall also incorporate a Symptom Checker and Triage engine that cross-references patient-reported symptoms with recorded vitals to produce structured triage outcomes, with all alert thresholds verified through unit testing and all visualisation views validated during integration testing.

**Objective 2** To implement an artificial intelligence-based health assessment module that employs Random Forest and XGBoost machine learning algorithms to simultaneously predict patient risk across five hypertension-related complications Stroke, Coronary Artery Disease, Heart Failure, Chronic Kidney Disease, and Type 2 Diabetes using twelve clinical and lifestyle input variables, achieving a minimum AUC-ROC of 0.80 for each complication predictor. The module shall categorise risk into four levels (Low, Moderate, High, and Critical) and complement the ML engine with a Google Gemini Flash-powered AI Health Agent capable of explaining risk scores in plain language and delivering contextual, personalised health guidance to patients.

**Objective 3** To develop a secure care coordination module that facilitates end-to-end encrypted messaging between patients and their assigned healthcare providers, supports shared care plan access across the full care team, and incorporates an NLP-based message scanner to automatically detect and escalate high-risk patient communications for urgent clinical attention. The module shall also deliver real-time emergency GPS alerts to linked family members when a patient's condition reaches a Critical risk threshold, and provide healthcare providers with an AI-prioritised patient dashboard filterable by predicted risk level to support proactive remote management.

#  

# 1.6 Project Scope

The scope of the Hypertension Care Management Platform defines the boundaries of what the system includes, who it serves, and the environment within which it operates.

**In Scope:**

The platform is designed for deployment within a Malaysian private hospital setting and serves five user roles: Patient, Healthcare Provider (Doctor), Family Member, Pharmacist, and Administrator. All thirteen modules are within scope: User and Access Management, Patient Health Overview, Vital Signs Tracking, Health Data Visualisation, Medication Management, Health Records Management, Appointment Scheduling, Healthcare Provider Portal, AI-Powered Health Monitoring, Care Coordination and Messaging, Admin Panel, Settings and Preferences, and Recurring Medication, Payment, and Delivery. All four cross-cutting features are within scope: AI Health Agent, Family Monitoring and Emergency Alert, Medication Delivery, and Symptom Checker and Triage.

The mobile application is developed for Android using Flutter, with the Flutter web build used for the administrative and healthcare provider portal. Third-party integrations within scope include Google Gemini Flash, Stripe Sandbox, Grab API, Google Maps API, SendGrid, and Twilio.

**Out of Scope:**

- iOS deployment: The application is developed and tested for Android only. iOS build and App Store submission are not included.

- Integration with existing Hospital Information Systems (HIS) or Electronic Medical Record (EMR) systems: The platform operates as a standalone system.

- Real Grab API production credentials: Medication delivery is implemented using the Grab API in sandbox/test mode only.

- Live Stripe payment processing: Stripe is integrated in sandbox mode only. Actual financial transactions are not processed.

- Clinical validation and regulatory approval: The platform is developed as an academic proof-of-concept and has not undergone clinical trials or medical device certification.

- Public hospital deployment: The system is scoped exclusively for the private hospital context.

- Multi-language support: The platform is implemented in English only.

#  

# 1.7 Existing or Similar Systems

A review of existing hypertension management applications identifies two leading consumer-facing tools Omron Connect and Withings Health Mate as the closest comparable systems to the Hypertension Care Management Platform. Both applications represent the current state of the art in commercially available hypertension self-management tools. However, a direct comparison reveals that both are limited to basic data capture and visualisation functions, and neither addresses the clinical intelligence, provider-facing tools, or care coordination capabilities that the platform is designed to deliver.

## 1.7.1 Omron Connect

Omron Connect is a companion application developed by Omron Healthcare for use with their range of proprietary blood pressure monitors and wearable devices. The application supports blood pressure logging and tracking, BP trend visualisation across multiple timeframes, and heart rate capture though heart rate measurement requires the use of Omron's dedicated hardware devices and is not available through the smartphone alone. Omron Connect is designed exclusively for patient self-monitoring and does not provide any clinician portal, healthcare provider access, or remote monitoring capability. There is no medication management feature, no appointment scheduling, no symptom triage, no AI-powered risk prediction, no secure messaging between patients and providers, and no mechanism for family members to monitor the patient's condition. The application addresses only the most basic layer of hypertension self-management and does not support any form of care coordination or clinical decision support (Lobo et al., 2023).

## 1.7.2 Withings Health Mate

Withings Health Mate is a health tracking platform that accompanies the Withings range of connected health devices, including blood pressure monitors, smartwatches, and body composition scales. The application supports blood pressure logging and tracking, BP trend visualisation, and heart rate monitoring though, as with Omron Connect, heart rate capture is dependent on proprietary Withings hardware and is not available to users without the corresponding device. Withings Health Mate is oriented toward general wellness tracking rather than condition-specific clinical management. It does not include a clinician portal, provider-facing dashboard, or any mechanism for remote patient monitoring by healthcare teams. There is no machine learning risk prediction, no AI health agent, no symptom checker, no encrypted patient-doctor messaging, no NLP-based message escalation, no medication management module, no recurring prescription or delivery workflow, no family monitoring feature, and no emergency GPS alert capability. Like Omron Connect, the application functions as a consumer self-monitoring tool and does not address the clinical coordination or intelligent monitoring gaps identified in the problem statement (Lobo et al., 2023).

## 1.7.3 Feature Comparison

The table below compares the Hypertension Care Management Platform against Omron Connect and Withings Health Mate across fourteen dimensions of clinical and operational capability.

| **Feature / Capability**                                       | **Omron Connect** | **Withings Health Mate** | **This Platform**        |
|----------------------------------------------------------------|-------------------|--------------------------|--------------------------|
| Blood Pressure Logging & Tracking                              | YES               | YES                      | YES                      |
| BP Trend Visualisation (7-day, 30-day, 3-month, 1-year)        | YES               | YES                      | YES                      |
| Heart Rate Capture                                             | Hardware Required | Hardware Required        | Camera PPG (No hardware) |
| ML Risk Prediction (5 complications, 12 variables)             | NO                | NO                       | YES                      |
| AI Health Agent / Chatbot (Google Gemini Flash)                | NO                | NO                       | YES                      |
| Symptom Checker & Clinical Triage                              | NO                | NO                       | YES                      |
| Healthcare Provider Portal (Doctor dashboard, risk alerts)     | NO                | NO                       | YES                      |
| Secure Encrypted Patient-Doctor Messaging with NLP Escalation  | NO                | NO                       | YES                      |
| Medication Management (Reminders, adherence, refills)          | NO                | NO                       | YES                      |
| Recurring Prescription & Home Delivery (Stripe + Grab API)     | NO                | NO                       | YES                      |
| Family Monitoring & Emergency GPS Alerts                       | NO                | NO                       | YES                      |
| Appointment Scheduling                                         | NO                | NO                       | YES                      |
| Hospital Workflow Integration (Admin panel, pharmacist module) | NO                | NO                       | YES                      |

Figure 1.7.2.1 shows system module organization chart in hypertension care management platform

Note: "YES" indicates native support within the application. "NO" indicates the feature is absent. "Hardware Required" means the feature depends on proprietary branded devices sold separately.

As the comparison demonstrates, Omron Connect and Withings Health Mate address only blood pressure logging and visualisation at a basic level, with heart rate capture restricted to users who purchase proprietary hardware. There is a demonstrated lack of apps with a clinician portal to support remote patient management, and apps integrated with wearable devices for lifestyle interventions in hypertension patients with a clinician portal are not widely available (Lobo et al., 2023). The Hypertension Care Management Platform closes all identified gaps within a single, unified application by integrating continuous monitoring, machine learning risk prediction, medication management, care coordination, family monitoring, and emergency alerting into one system designed specifically for the Malaysian private hospital setting.

# 1.8 Advantages and Contribution

The Hypertension Care Management Platform addresses gaps that existing hypertension management tools have consistently failed to close. Its advantages are assessed both against consumer-facing applications such as Omron Connect and Withings Health Mate, and against the broader landscape of digital health platforms. While there has been remarkable progress in digital health innovations for hypertension management, further larger-scale controlled studies and research demonstrating utility in real-world clinical settings are necessary to establish more robust evidence regarding the effectiveness of mHealth apps (Nozato & Yamamoto, 2024).

## 1.8.1 Advantages

**1. Unified, Hypertension-Specific Platform**

Existing tools address individual aspects of hypertension management in isolation Omron Connect handles BP logging, HealthTap handles doctor messaging, and separate pharmacy apps handle medication delivery. None integrate these functions into a single, condition-specific application. The platform consolidates blood pressure tracking, heart rate capture, ML risk prediction, medication management, symptom triage, care coordination, family monitoring, and medication delivery into one unified system. This eliminates the need for patients to navigate multiple disconnected applications and provides healthcare providers with a holistic, real-time view of each patient's condition.

**2. Multi-Complication Machine Learning Risk Prediction**

No existing consumer hypertension application incorporates predictive analytics beyond simple BP threshold alerts. The platform's ML engine, trained on validated clinical datasets including the Framingham Heart Study dataset and the Pima Indians Diabetes Database, simultaneously predicts patient risk across five complications Stroke, Coronary Artery Disease, Heart Failure, Chronic Kidney Disease, and Type 2 Diabetes using twelve input variables. Machine learning models can enhance predictive power by detecting complex, non-linear interactions among co-occurring risk factors (Abramowitz et al., 2023).

**3. Dedicated Healthcare Provider Portal with AI-Prioritised Alerts**

Omron Connect, Withings Health Mate, and similar apps are built exclusively for patients. They offer no portal, no clinical workflow support, and no mechanism for healthcare providers to monitor patients remotely or receive risk-based alerts (Lobo et al., 2023). The platform's Healthcare Provider Portal allows doctors to manage their assigned patient list filtered by ML-predicted risk level, write clinical notes, issue prescriptions, and receive AI-prioritised deterioration alerts when a patient's risk worsens steadily over 30 days.

**4. NLP-Powered Urgent Message Escalation**

Existing secure messaging implementations in health platforms where they exist at all treat all messages equally, placing the burden on the healthcare provider to identify and respond to critical communications. The platform's NLP Message Analysis scanner automatically detects high-risk keywords in patient messages and escalates flagged conversations as urgent to the assigned doctor, ensuring that critical patient communications are never delayed or overlooked in a high-volume inbox (Mermin-Bunnell et al., 2023).

**5. Family Monitoring and Emergency GPS Integration**

No existing hypertension application extends real-time health visibility to family members (WHO, 2023). The Family Monitoring and Emergency Alert feature allows linked family members to view the patient's blood pressure readings and health status at any time, receive automatic emergency alerts with the patient's live GPS location when condition reaches a Critical threshold, and access a one-tap emergency call button transforming family members into active participants in the patient's care. This is a meaningful contribution in the Malaysian healthcare context, where family involvement in chronic disease management is both culturally expected and clinically beneficial (Muehlensiepen et al., 2024).

**6. End-to-End Recurring Medication Management and Home Delivery**

Existing platforms, including those with medication reminder functionality, do not address the full medication lifecycle. The platform closes this gap through an end-to-end recurring prescription workflow: doctors flag long-term chronic patients and issue recurring prescriptions; the system automatically notifies patients monthly to confirm their order; payment is processed via Stripe; the pharmacist is notified to prepare the medication; and home delivery is dispatched via the Grab API with real-time doorstep tracking. This removes the logistical burden of manual refill management from both the patient and the care team, directly addressing the medication non-adherence challenge documented globally (Lee et al., 2022; Lim et al., 2025).

**7. Hardware-Independent Heart Rate Capture**

Unlike Omron Connect and Withings Health Mate, which require proprietary hardware devices, the platform captures heart rate using Mobile Camera PPG, a technique where the patient places their finger over the smartphone camera to detect blood volume changes via green-channel pixel intensity analysis and peak detection algorithms (Cite Benezeth et al., 2023) . This makes advanced physiological monitoring accessible to any patient with a standard smartphone, removing the cost and accessibility barrier of dedicated medical hardware.

## 1.8.2 Limitations

Despite its contributions, the Hypertension Care Management Platform is subject to several limitations that should be acknowledged.

First, the ML Disease Risk Prediction engine is trained on publicly available Kaggle datasets that, while clinically validated, may not fully reflect the demographic and clinical profile of the Malaysian hypertension patient population. Further validation against a locally sourced clinical dataset would be necessary before any real-world clinical deployment.

Second, the mobile camera PPG heart rate capture method, while accessible and hardware-free, is inherently less accurate than dedicated medical pulse oximeters or ECG devices. Measurement quality can be affected by ambient lighting conditions, fingertip placement consistency, and the optical characteristics of individual smartphone cameras (Mather et al., 2024; Benezeth et al., 2023). The platform presents PPG readings as supplementary data points within the triage engine rather than as medically certifiable measurements.

Third, the NLP Message Analysis scanner is implemented as a rule-based keyword detection system. It may produce false positives for messages that contain high-risk terms in a non-urgent context (e.g., "I no longer have chest pain") or miss urgent messages phrased in ways that do not match the predefined keyword list.

Fourth, the platform is scoped for Android only and has not been tested or optimised for iOS. Fifth, the platform is deployed as an academic proof-of-concept and has not undergone clinical validation, regulatory review, or certification as a medical device. It should not be used for clinical decision-making in its current form without further validation and regulatory approval.

## 1.8.3 Sustainability Contribution (SDG Alignment)

**SDG 3: Good Health and Well-Being**

The platform directly advances SDG 3 by providing a digital infrastructure that supports continuous hypertension monitoring, early complication detection, and improved medication adherence. Hypertension is one of the leading preventable causes of cardiovascular disease and premature death globally (WHO, 2023). By enabling proactive management and reducing preventable complications, the platform contributes to the SDG 3 targets of reducing premature mortality from non-communicable diseases and achieving universal access to quality healthcare services.

**SDG 10: Reduced Inequalities**

The hardware-independent design of the platform using mobile camera PPG for heart rate capture rather than proprietary medical devices removes a key financial barrier to advanced health monitoring. Patients with standard Android smartphones can access clinical-grade monitoring capabilities without purchasing dedicated hardware, making the platform more equitable across different socioeconomic groups.

**SDG 17: Partnerships for the Goals**

The platform is built on an ecosystem of technology partnerships Google Gemini Flash for AI, Grab for medication delivery, Stripe for payments, Firebase for backend infrastructure, and Google Maps for emergency GPS tracking. This multi-partner architecture demonstrates how cross-sector technology collaboration can be harnessed to deliver health outcomes, aligning with the SDG 17 principle of mobilising multi-stakeholder partnerships for sustainable development goals.

# 1.9 System Development Methodology and Project Plan

## 1.9.1 Methodology

This project adopts the Incremental Development model as the primary system development methodology. Under this model, the system is designed in full at the outset and then built and delivered across a series of self-contained increments, each of which produces a functional, testable subset of the complete system. Each increment follows its own cycle of requirements definition, design, implementation, and testing before the next increment begins.

The Incremental model is selected over alternative methodologies for the following reasons. The Waterfall model, while straightforward to document, assumes that all requirements are fully stable and that no module will need to be revisited once development has passed that stage an assumption that is unsuitable for a system of this complexity, where ML model integration, third-party API behaviour (Stripe, Grab, Google Gemini Flash), and camera PPG implementation are likely to require adjustment as development progresses. The Prototyping model is oriented toward projects where requirements are uncertain and need to be discovered through iterative user feedback; the requirements for the Hypertension Care Management Platform are already well-defined across five user roles, thirteen modules, and four cross-cutting features, making prototyping an ill-fitting justification. Agile Scrum, while flexible, is designed primarily for team-based development with sprint ceremonies, daily standups, and collaborative backlogs; applying it to a solo development context introduces process overhead without meaningful benefit.

The Incremental model balances structured documentation with development practicality. High-priority core modules are functional and independently testable from early in the project, reducing the risk of late-stage integration failures. Each increment is fully documented with its own requirements, design decisions, and test outcomes, providing a clear audit trail for the FYP report across Chapters 3 and 4.

## 1.9.2 Development Phases

Development is structured across five increments, preceded by a planning phase and followed by a testing and documentation phase.

Phase 1 Requirements Gathering and System Planning (Weeks 1–9)

All system requirements are gathered and documented before incremental development begins. Activities include a structured review of academic literature on hypertension mHealth, ML-based clinical risk prediction, and digital health platform design. User stories and functional requirements are defined for all five user roles. The complete system architecture covering the Flutter frontend, Firebase backend, ML model pipeline, and third-party API integrations is designed and documented. UI/UX wireframes and prototypes are produced for all thirteen modules and four cross-cutting features.

Phase 2 Increment 1: Core System and Patient Monitoring (Weeks 9–11)

The Flutter project structure is initialised and the Firebase backend is configured, including Firestore database schema and role-based access control for all five user roles. The User and Access Management module, Patient Health Overview dashboard, Vital Signs Tracking module with manual blood pressure logging, mobile camera PPG heart rate capture, and Health Data Visualisation module with 7-day, 30-day, 3-month, and 1-year trend views are developed and tested. This increment delivers the foundational monitoring capability of the platform and is independently functional and testable upon completion.

Phase 3 Increment 2: AI and Clinical Intelligence (Weeks 11–13)

The ML Disease Risk Prediction engine is built using Random Forest and XGBoost algorithms, trained on validated clinical datasets, and integrated into the backend to generate real-time risk scores across five hypertension-related complications. The AI Health Agent is implemented via the Google Gemini Flash API. The Symptom Checker and Triage engine is developed, incorporating cross-referencing of patient-reported symptoms, blood pressure, PPG heart rate, and ML risk scores to produce structured triage outcomes. The Healthcare Provider Portal is developed to support doctor-side risk monitoring and patient management. This increment is tested independently before Phase 4 begins.

Phase 4 Increment 3: Care Coordination, Medication, and Extended Features (Weeks 13–15)

The Care Coordination and Messaging module is built with end-to-end encrypted patient-doctor messaging and the NLP Message Analysis scanner for automatic high-risk keyword detection and urgent escalation. The Family Monitoring and Emergency GPS Alert feature is implemented, enabling linked family members to view real-time patient health status and receive automatic Critical-threshold alerts with live GPS location. The Medication Management module is implemented with dosage scheduling, push notification reminders, missed dose logging, adherence rate tracking, and refill alerts. The Recurring Medication, Payment, and Delivery module is integrated with the Stripe payment gateway and the Grab API for automated monthly prescription fulfilment and real-time home delivery tracking. All remaining modules Appointment Scheduling, Health Records Management, Admin Panel, and Settings and Preferences are finalised in this increment.

Phase 5 Integration Testing and Refinement (Weeks 15–17)

Following the completion of all three increments, full system integration testing is conducted to verify that all modules interact correctly across the complete system. Unit tests, integration tests, and User Acceptance Testing (UAT) are conducted with representative users from all five role groups. Identified defects are resolved and regression-tested.

Phase 6 Documentation and Submission (Weeks 17–20)

Final system documentation, user guides, supervisor and moderator demonstration, and the complete FYP report are produced and submitted.

## 1.9.3 Project Schedule

| Phase                                        | Key Activities                                                                                                         | Duration    |
|----------------------------------------------|------------------------------------------------------------------------------------------------------------------------|-------------|
| Phase 1: Planning                            | Literature review, requirements, architecture design, wireframes, project plan                                         | Weeks 1–9   |
| Phase 2 Increment 1: Core System             | Flutter setup, Firebase backend, authentication, RBAC, BP logging, PPG capture, health data visualisation              | Weeks 9-11  |
| Phase 3 Increment 2: AI & Clinical           | ML risk prediction engine, AI Health Agent, Symptom Checker & Triage, Healthcare Provider Portal                       | Weeks 11–13 |
| Phase 4 Increment 3: Coordination & Features | Messaging & NLP escalation, Family GPS alerts. Medication management, Stripe & Grab API integration, remaining modules | Weeks 13–15 |
| Phase 5 Testing & Refinement                 | Unit testing, integration testing, UAT, defect resolution                                                              | Weeks 15–17 |
| Phase 6 Documentation and Submission         | Final documentation, Presentation and Submission                                                                       | Weeks 17-20 |

### 1.9.3.1 Project Schedule (Gantt Chart)


Figure 1.4.3.1 shows Gantt Chart for the development phase

The chart above maps each development activity to its scheduled weeks across the 6 month project timeline. Filled cells represent active project weeks for each activity.

# 1.10 Project Team and Organisation

The Hypertension Care Management Platform is developed as an individual Final Year Project. All phases of the project including system design, frontend and backend development, ML model implementation, testing, and documentation are carried out by a single developer.

## 1.10.1 Developer

Woo Yee Ping is responsible for the full project lifecycle, encompassing:

- Requirements gathering and functional specification for all five user roles

- UI/UX wireframing and prototype design for all 13 modules and 4 features

- Flutter frontend implementation for Android

- Firebase backend setup, Firestore schema design, and role-based access control

- Mobile camera PPG integration for heart rate capture

- ML Disease Risk Prediction engine development using Random Forest and XGBoost

- AI Health Agent integration via Google Gemini Flash API

- NLP Message Analysis scanner for keyword-based escalation

- Stripe payment gateway and Grab API integration for recurring medication delivery

- Google Maps API integration for family emergency GPS tracking

- Unit testing, integration testing, and User Acceptance Testing coordination

- Technical documentation and FYP report

## 1.10.2 Organisation Chart


Figure 1.10.2.1 shows system module organization chart in hypertension care management platform

#  

# 1.11 Chapter Summary

This chapter introduced the Hypertension Care Management Platform and established the foundation for the project by presenting its background, problem statement, proposed solutions, objectives, scope, existing systems review, advantages, development methodology, and organisational structure.

Section 1.1 highlighted hypertension as a major global and Malaysian health concern (WHO, 2023; Institute for Public Health, 2024), discussed the limitations of current clinic-centric management approaches (Lobo et al., 2023), and introduced the proposed platform as a Flutter-based mobile application that integrates health monitoring, machine learning risk prediction, medication management, care coordination, and emergency support within a single system for use in Malaysian private hospitals.

Section 1.2 examined the current hypertension management landscape and identified three structural gaps: the absence of continuous monitoring between clinic visits (Ibrahim et al., 2022; Lobo et al., 2023), poor medication adherence support (Lee et al., 2022), and fragmented communication and data across care stakeholders (Tee et al., 2025; Loo et al., 2023).

Section 1.3 defined the three core problems driving the need for the platform: the lack of continuous between-visit monitoring, poor medication adherence support, and fragmented care coordination across patients, providers, family members, and pharmacists (Shahid et al., 2022).

Section 1.4 described the platform's proposed solutions across three problem domains, detailing the integrated components addressing continuous monitoring, medication non-adherence, and care coordination, including mobile camera PPG, the ML Disease Risk Prediction engine, encrypted messaging with NLP escalation, and the recurring prescription and home delivery workflow.

Section 1.5 presented three SMART project objectives: (1) to design and develop a hypertension-focused patient monitoring system enabling continuous BP tracking, health data visualisation, and threshold-based alerts; (2) to implement an AI-powered health assessment module with ML disease risk prediction across five complications achieving a minimum AUC-ROC of 0.80; and (3) to develop a secure care coordination module facilitating encrypted messaging, NLP-based escalation, real-time emergency GPS alerts, and an AI-prioritised provider dashboard.

Section 1.6 defined the project scope, clarifying what is included and excluded from the system, covering five user roles, thirteen modules, four cross-cutting features, and third-party integrations, and excluding iOS deployment, HIS/EMR integration, live payment processing, and clinical regulatory approval.

Section 1.7 reviewed two leading comparable systems Omron Connect and Withings Health Mate and presented a Feature Comparison Table benchmarking the platform against both across fourteen capability dimensions, demonstrating that neither existing system addresses clinical intelligence, provider-facing tools, or care coordination.

Section 1.8 discussed the key advantages and contributions of the proposed platform across seven dimensions, acknowledged its limitations including dataset generalisability, PPG measurement accuracy, and NLP keyword coverage, and outlined its alignment to SDG 3 (Good Health and Well-Being), SDG 10 (Reduced Inequalities), and SDG 17 (Partnerships for the Goals).

Section 1.9 described the Incremental Development methodology adopted for system development and presented the six-phase development plan structured across three functional increments. A full Gantt Chart mapping all development activities across the 22-week project timeline was provided.

Section 1.10 introduced the project team and outlined the full scope of responsibilities undertaken by the sole developer across all phases of the project lifecycle.

The next chapter will present a detailed literature review covering hypertension management systems, mobile health technologies, machine learning applications in healthcare, and care coordination platforms relevant to the development of the proposed solution.

# 1.12 References

1.  World Health Organization. (2023). *Global report on hypertension: The race against a silent killer*. World Health Organization. [<u>https://www.who.int/publications/i/item/9789240081062</u>](https://www.who.int/publications/i/item/9789240081062)

2.  World Health Organization. (2024). *Hypertension fact sheet*. World Health Organization. [<u>https://www.who.int/news-room/fact-sheets/detail/hypertension</u>](https://www.who.int/news-room/fact-sheets/detail/hypertension)

3.  Institute for Public Health, Ministry of Health Malaysia. (2024). *National Health and Morbidity Survey (NHMS) 2023: Non-communicable diseases*. Ministry of Health Malaysia.

4.  Loo, J. S., Yow, H. Y., Ten, Y. Y., Govindaraju, K., Megat Mohd Zubairi, M. H., Oui, H. C., & Abdul Rahim, N. (2023). Exploring the rise of telehealth services in Malaysia: A retrospective study. *Digital Health*, *9*, 20552076231216275. [<u>https://doi.org/10.1177/20552076231216275</u>](https://doi.org/10.1177/20552076231216275)

5.  Mahadir Naidu, B., Mohd Yusoff, M. F., Abdullah, S., Musa, K. I., Yaacob, N. M., Mohamad, M. S., Sahril, N., & Aris, T. (2018). Prevalence, awareness, treatment and control of hypertension in Malaysia: Findings from the National Health and Morbidity Survey 2006–2015. *Journal of Human Hypertension*, *33*(2), 142–150. [<u>https://doi.org/10.1038/s41371-018-0082-x</u>](https://doi.org/10.1038/s41371-018-0082-x)

6.  Ibrahim, N., Mohd Zaki, R., Che Roos, N. A., Shamsuddin, K., Jatau, A. I., & Awang Besar, J. (2022). The determinants of undiagnosed hypertension among urban community of Kuala Lumpur, Malaysia. *Iranian Journal of Public Health*, *51*(6), 1348–1358. [<u>https://pmc.ncbi.nlm.nih.gov/articles/PMC9659544/</u>](https://pmc.ncbi.nlm.nih.gov/articles/PMC9659544/)

7.  Lee, E. K. P., Poon, P., Yip, B. H. K., Bo, Y., Zhu, M.-T., Yu, C.-P., Ngai, A. C. H., Wong, M. C. S., & Wong, S. Y. S. (2022). Global burden, regional differences, trends, and health consequences of medication nonadherence for hypertension during 2010 to 2020: A meta-analysis involving 27 million patients. *Journal of the American Heart Association*, *11*(17), e026582. [<u>https://doi.org/10.1161/JAHA.122.026582</u>](https://doi.org/10.1161/JAHA.122.026582)

8.  Abramowitz, M. K., Hall, C. B., Amodu, A., Sharma, D., Androga, L., & Hawkins, M. (2023). The impact of non-adherence to antihypertensive drug therapy. *Pharmacy (Basel)*, *11*(6), 177. [<u>https://pmc.ncbi.nlm.nih.gov/articles/PMC10671374/</u>](https://pmc.ncbi.nlm.nih.gov/articles/PMC10671374/)

9.  Muehlensiepen, F., Bruch, D., Seifert, F., Wengemuth, E., Heinze, M., Spethmann, S., & May, S. (2024). mHealth apps for hypertension self-management: Interview study among patient-users. *JMIR Formative Research*, *8*, e56162. [<u>https://doi.org/10.2196/56162</u>](https://doi.org/10.2196/56162)

10. Liu, F., Song, T., Yu, P., Deng, N., Guan, Y., Yang, Y., & Ma, Y. (2023). Efficacy of an mHealth app to support patients' self-management of hypertension: Randomized controlled trial. *Journal of Medical Internet Research*, *25*, e43809. [<u>https://doi.org/10.2196/43809</u>](https://doi.org/10.2196/43809)

11. Lobo, E. H., Karmakar, C., Abdelrazek, M., Abawajy, J., Chow, C. K., Zhang, Y., Kabir, M. A., Daryabeygi, R., Maddison, R., & Islam, S. M. S. (2023). Design and development of a smartphone app for hypertension management: An intervention mapping approach. *Frontiers in Public Health*, *11*, 1092755. [<u>https://doi.org/10.3389/fpubh.2023.1092755</u>](https://doi.org/10.3389/fpubh.2023.1092755)

12. Wu, Y., Xin, B., Wan, Q., Ren, Y., & Jiang, W. (2024). Risk factors and prediction models for cardiovascular complications of hypertension in older adults with machine learning: A cross-sectional study. *Heliyon*, *10*(6), e27941. [<u>https://doi.org/10.1016/j.heliyon.2024.e27941</u>](https://doi.org/10.1016/j.heliyon.2024.e27941)

13. Pong, C., Tseng, R. M. W. W., Tham, Y. C., & Lum, E. (2024). Current implementation of digital health in chronic disease management: Scoping review. *Journal of Medical Internet Research*, *26*, e53576. [<u>https://doi.org/10.2196/53576</u>](https://doi.org/10.2196/53576)

14. Omar, S. M., Gasim, G. I., Musa, I. R., & Adam, I. (2023). Prevalence and factors associated with prehypertension and hypertension among adults: Baseline findings of PURE Malaysia cohort study. *Vascular Health and Risk Management*, *19*, 389–399. [<u>https://doi.org/10.2147/VHRM.S413613</u>](https://doi.org/10.2147/VHRM.S413613)

15. Zawawi, N. H., Chia, Y. C., Wan Ahmad, W. A., Fong, A. Y. Y., Rosman, A., Ahmad, W. A. W., & Shahrir, M. S. (2022). 2022 Malaysian Working Group Consensus Statement on Renal Denervation for management of arterial hypertension. *Hypertension Research*, *45*(7), 1111–1122. [<u>https://pmc.ncbi.nlm.nih.gov/articles/PMC9192347/</u>](https://pmc.ncbi.nlm.nih.gov/articles/PMC9192347/)

16. Tee, E. S., Chan, P., Lim, K. H., & Lim, K. K. (2025). The evolution of healthcare digitalisation policies in Malaysia: A four-decade narrative review (1985–2025). *Digital Health*, *11*. [<u>https://pmc.ncbi.nlm.nih.gov/articles/PMC12227897/</u>](https://pmc.ncbi.nlm.nih.gov/articles/PMC12227897/)

17. Nakrys, M., Valinskas, S., Aleknavičius, K., & Jonusas, J. (2023). Pilot investigation of blood pressure control using a mobile app (Cardi.Health): Retrospective chart review study. *JMIR Cardio*, *7*, e48454. [<u>https://doi.org/10.2196/48454</u>](https://doi.org/10.2196/48454)

18. Nozato, Y., & Yamamoto, K. (2024). The effects of smartphone apps expected in self-management for hypertension management. *Hypertension Research*, *47*, 1087–1089. [<u>https://doi.org/10.1038/s41440-023-01516-3</u>](https://doi.org/10.1038/s41440-023-01516-3)

19. Mather, J. D. (2024, February 29). Validity of resting heart rate derived from contact-based smartphone photoplethysmography compared with electrocardiography: A scoping review and checklist for optimal acquisition and reporting. *Frontiers in Digital Health, 6*. [<u>https://doi.org/10.3389/fdgth.2024.1326511</u>](https://doi.org/10.3389/fdgth.2024.1326511)

20. Mermin-Bunnell, K. (2023, June). Use of natural language processing of patient-initiated electronic health record messages to identify patients with COVID-19 infection. *JAMA Network Open*. [<u>https://jamanetwork.com/journals/jamanetworkopen/fullarticle/2807055</u>](https://jamanetwork.com/journals/jamanetworkopen/fullarticle/2807055)

21. Natural language processing system for rapid detection and intervention of mental health crisis chat messages. (2023, November 21). *npj Digital Medicine*. [<u>https://www.nature.com/articles/s41746-023-00951-3</u>](https://www.nature.com/articles/s41746-023-00951-3)

22. Gazit, T. (2024, November 1). A novel, machine-learning model for prediction of short-term ASCVD risk over 90 and 365 days. *PubMed Central*. [<u>https://pmc.ncbi.nlm.nih.gov/articles/PMC11564171/</u>](https://pmc.ncbi.nlm.nih.gov/articles/PMC11564171/)

23. Wang, T. (2024, November 8). Exploration of features of mobile applications for medication adherence in Asia: Narrative review. *Journal of Medical Internet Research*. [<u>https://www.jmir.org/2024/1/e60787</u>](https://www.jmir.org/2024/1/e60787)

24. Lanke, V. (2025, July 31). Evaluating the effectiveness of mobile apps on medication adherence for chronic conditions: Systematic review and meta-analysis. *PubMed Central*. [<u>https://pmc.ncbi.nlm.nih.gov/articles/PMC12312993/</u>](https://pmc.ncbi.nlm.nih.gov/articles/PMC12312993/)

25. Xuan, Y. (2023, November 24). A calibration method for smartphone camera photoplethysmography. *Frontiers in Digital Health*. [<u>https://www.frontiersin.org/journals/digital-health/articles/10.3389/fdgth.2023.1301019/full</u>](https://www.frontiersin.org/journals/digital-health/articles/10.3389/fdgth.2023.1301019/full)
