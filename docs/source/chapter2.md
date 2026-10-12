Chapter 2

# Literature Review

##  

## Table content

[**Literature Review 1**](#literature-review)

> [Table content 2](#table-content)
>
> [2.1 Overview of Hypertension and Its Global Burden 2](#section-1)
>
> [2.2 Hypertension Management: Challenges and Limitations 5](#hypertension-management-challenges-and-limitations)
>
> [2.2.1 Limitations of Clinic-Centric Monitoring 5](#limitations-of-clinic-centric-monitoring)
>
> [2.2.2 Medication Non-Adherence 6](#medication-non-adherence)
>
> [2.2.3 Fragmented Care Coordination 7](#fragmented-care-coordination)
>
> [2.3 Mobile Health Applications for Hypertension Management 9](#mobile-health-applications-for-hypertension-management)
>
> [2.3.1 Omron Connect 10](#omron-connect)
>
> [2.3.2 Withings Health Mate 10](#withings-health-mate)
>
> [2.3.3 SmartBP Blood Pressure Monitor 11](#smartbp-blood-pressure-monitor)
>
> [2.3.4 Cardi.Health 12](#cardi.health)
>
> [2.3.5 Comparative Feature Analysis 13](#comparative-feature-analysis)
>
> [2.4 Research Gap 17](#research-gap)
>
> [2.5 Technologies Used in Existing Hypertension Management Systems 19](#technologies-used-in-existing-hypertension-management-systems)
>
> [2.5.1 Mobile Development Frameworks 20](#mobile-development-frameworks)
>
> [2.5.2 Backend and Database Technologies 20](#backend-and-database-technologies)
>
> [2.5.3 Machine Learning and AI 21](#machine-learning-and-ai)
>
> [2.5.4 Communication and Notification Technologies 22](#communication-and-notification-technologies)
>
> [2.6 Technologies Proposed for the Hypertension Care Management Platform 23](#technologies-proposed-for-the-hypertension-care-management-platform)
>
> [2.6.1 Flutter as the Cross-Platform Development Framework 23](#flutter-as-the-cross-platform-development-framework)
>
> [2.6.2 Firebase as the Backend and Database Platform 25](#firebase-as-the-backend-and-database-platform)
>
> [2.6.3 Machine Learning: Random Forest and XGBoost for Disease Risk Prediction 26](#machine-learning-random-forest-and-xgboost-for-disease-risk-prediction)
>
> [2.6.4 Mobile Camera Photoplethysmography (PPG) for Heart Rate Detection 29](#mobile-camera-photoplethysmography-ppg-for-heart-rate-detection)
>
> [2.6.5 Google Gemini Flash as the AI Health Agent 30](#google-gemini-flash-as-the-ai-health-agent)
>
> [2.6.6 NLP-Based Message Analysis for Urgent Escalation 31](#nlp-based-message-analysis-for-urgent-escalation)
>
> [2.6.7 Stripe Payment Gateway and Grab API for Medication Delivery 32](#stripe-payment-gateway-and-grab-api-for-medication-delivery)
>
> [2.7 Feasibility Study 33](#feasibility-study)
>
> [2.7.1 Technical Feasibility 33](#technical-feasibility)
>
> [2.7.2 Economic Feasibility 34](#economic-feasibility)
>
> [2.7.3 Social Feasibility 34](#social-feasibility)
>
> [2.7.4 Operational Feasibility 35](#operational-feasibility)
>
> [2.7.5 Schedule Feasibility 36](#schedule-feasibility)
>
> [2.8 Chapter Summary 38](#chapter-summary)
>
> [2.9 References 41](#references)

##   

## 2.1 Overview of Hypertension and Its Global Burden

Hypertension, clinically defined as a sustained systolic blood pressure of 130 mmHg or higher or diastolic blood pressure of 80 mmHg or higher, represents one of the most pervasive and clinically significant chronic non-communicable diseases of the modern era. It is widely recognised as a primary modifiable risk factor for cardiovascular disease, stroke, chronic kidney disease, and premature death. The condition is particularly insidious because of its largely asymptomatic nature: most patients experience no discernible symptoms despite carrying dangerously elevated blood pressure readings for months or years, which is why hypertension is frequently described in clinical literature as the silent killer (WHO, 2023).

The global scale of hypertension is extraordinary. The World Health Organization estimates that approximately 1.28 billion adults worldwide are currently living with hypertension, yet nearly half of this population, approximately 580 million individuals, remain entirely unaware of their condition (WHO, 2023). This diagnostic gap is attributable to multiple factors: limited access to blood pressure screening infrastructure in low- and middle-income countries, a general absence of symptoms that might prompt individuals to seek medical attention, and the high cost of routine healthcare in settings without universal coverage. The consequence is that millions of people continue to carry unmanaged risk for catastrophic cardiovascular events without knowledge of their condition or access to appropriate treatment.

Hypertension exerts its damage through a cumulative, progressive mechanism. Chronically elevated blood pressure forces the heart to work harder with each contraction, gradually thickening the muscular walls of the left ventricle and reducing its capacity to pump blood efficiently, a process known as hypertensive heart disease. Simultaneously, sustained high pressure damages the delicate endothelial lining of blood vessel walls throughout the body, accelerating the formation of atherosclerotic plaques, increasing the risk of plaque rupture, and raising the probability of arterial occlusion events such as myocardial infarction and ischaemic stroke. In the kidneys, chronically elevated intra-glomerular pressure impairs the filtration apparatus over time, progressively reducing glomerular filtration rate and eventually leading to hypertensive nephropathy or end-stage renal disease (WHO, 2023). These downstream complications collectively account for tens of millions of disability-adjusted life years lost globally each year.

In the Malaysian context, the hypertension burden is substantial and has demonstrated a persistent upward trajectory over several decades. The National Health and Morbidity Survey (NHMS) documented a prevalence of 32.9% in 1996, which rose to 34.6% in 2006 and 35.3% in 2015, establishing hypertension as one of the leading contributors to cardiovascular morbidity and premature death in the country (Ab Majid et al., 2018). The NHMS 2023 reported a hypertension prevalence of 29.2% among Malaysian adults, representing approximately 6.7 million individuals (Institute for Public Health, Ministry of Health Malaysia, 2024). Among those affected, a substantial proportion remain undiagnosed: Ibrahim et al. (2022) identified that for every two persons diagnosed with hypertension in Malaysia, there are approximately three persons with undiagnosed hypertension, a ratio that has persisted largely unchanged since 2011. This persistent diagnostic gap underscores the inadequacy of current screening and monitoring frameworks and highlights the urgent need for interventions capable of extending monitoring coverage beyond the clinical setting.

Taken together, these figures indicate that a substantial proportion of the Malaysian hypertensive population remains either undiagnosed or inadequately monitored between clinical encounters, a structural weakness in the prevailing care model rather than a failure of any individual patient or clinician. Section 2.2 examines this weakness in detail, analysing the specific limitations of clinic-centric monitoring, medication adherence, and care coordination that allow this diagnostic and management gap to persist.

##  

## 2.2 Hypertension Management: Challenges and Limitations

Effective hypertension management requires consistent, long-term engagement across three dimensions: continuous physiological monitoring, sustained medication adherence, and coordinated communication between patients and their care teams. The prevailing model of hypertension management in both Malaysia and globally fails to adequately address any of these three dimensions, resulting in a care environment that is reactive rather than proactive, episodic rather than continuous, and fragmented rather than coordinated. Three major, interrelated challenges arise from this failure and are examined in the subsections that follow: the structural inadequacy of clinic-centric monitoring for a condition as dynamic as hypertension (Section 2.2.1), the persistent global and Malaysian epidemic of anti-hypertensive medication non-adherence (Section 2.2.2), and the fragmentation of care coordination across patients, providers, pharmacists, and family members (Section 2.2.3).

### 2.2.1 Limitations of Clinic-Centric Monitoring

The dominant model of hypertension monitoring is clinic-centric: patients attend periodic consultations at scheduled intervals, have their blood pressure measured at the point of care, and are discharged until the next appointment. While this approach is adequate for patients whose blood pressure is well-controlled and stable, it is structurally ill-suited for a condition as dynamic as hypertension. Blood pressure is not a static physiological parameter; it fluctuates substantially throughout the day in response to physical activity, psychological stress, dietary sodium intake, sleep quality, circadian rhythms, and medication timing (WHO, 2023).

A single blood pressure reading obtained during a clinic visit may not accurately represent the patient's true blood pressure profile over the preceding weeks or months. The phenomenon of masked hypertension, in which blood pressure appears normal during clinic visits but is elevated during daily life, is a recognised clinical problem and a documented risk factor for end-organ damage even in patients who appear well-controlled during consultations (Nakrys et al., 2023). The inverse phenomenon, white-coat hypertension, in which anxiety related to the clinical environment artificially elevates readings, is equally problematic. Both phenomena are only detectable through continuous or ambulatory blood pressure monitoring, which is not feasible within a clinic-visit-only model.

The collective consequence of these limitations is that clinic-based monitoring alone is insufficient to capture the true blood pressure burden of most patients. Clinically significant elevations occurring between appointments go entirely undetected. Warning signs of imminent deterioration, such as gradually rising average readings over several weeks, remain invisible to the care team. By the time the patient presents for their next scheduled consultation, the window for early intervention may have closed and the patient may already be experiencing hypertension-related organ damage. A comprehensive review of existing hypertension applications concluded that there is a demonstrated lack of apps with a clinician portal to support remote patient management, and applications integrated with wearable devices for lifestyle interventions in people with hypertension with a clinician portal are not widely available (Lobo et al., 2023).

Collectively, these blind spots in the clinic-visit-only model make a compelling case for remote monitoring technologies: only a system capable of capturing blood pressure readings continuously between appointments, detecting deteriorating trends as they emerge, and surfacing this information to the care team in real time can close the diagnostic and intervention gap that the clinic-centric model leaves open.

### 2.2.2 Medication Non-Adherence

Anti-hypertensive medication non-adherence is the leading cause of poor blood pressure control worldwide and a primary driver of cardiovascular disease and preventable mortality. A meta-analysis drawing on data from 2010 to 2020 and covering 27 million patients recorded global non-adherence rates of 27% to 40%, with up to 50% of patients discontinuing their prescribed antihypertensive medications entirely within one year of initiation (Lee et al., 2022). Non-adherence is not a monolithic behaviour; it encompasses a spectrum from occasional missed doses to complete discontinuation, and its causes are multifactorial, including medication side effects, asymptomatic disease perception, cost of medications, complex dosing schedules, and a lack of structured support mechanisms between clinic visits.

The Malaysian evidence reinforces this global picture while also pointing to a gradual improvement over time. An early multicentre study conducted across primary health clinics in the Hulu Langat district of Selangor found an overall adherence rate of approximately 50%, with adherence falling to as low as 27.1% among patients held to the strictest adherence criterion (Ramli et al., 2012). More recent Malaysian data suggest some improvement: a 2024 cross-sectional survey of 1,531 hypertensive patients across public primary health clinics in the Melaka Tengah District reported that 74.1% had good antihypertensive medication adherence, with non-adherence significantly associated with Malay ethnicity, secondary-level education, greater distance from the clinic, experience of medication side effects, concern about long-term side effects, and use of alternative medicine (Suleiman et al., 2024). Despite this apparent improvement relative to earlier studies, roughly one in four Malaysian hypertensive patients in primary care remains non-adherent, and adherence was also found to be significantly associated with blood pressure control, underscoring that non-adherence continues to translate directly into poorer clinical outcomes in the Malaysian setting (Suleiman et al., 2024).

In the current clinic-centric model, once a patient leaves the consultation room, no structured mechanism exists to remind them to take medications, track whether doses are missed, alert the care team when adherence deteriorates, or facilitate timely prescription refills (Wang et al., 2024). The consequence is that missed doses go unrecorded and unaddressed, silently allowing blood pressure to rise unchecked and accelerating the progression of hypertension-related complications. At the population level, the cumulative burden of non-adherence translates directly into higher rates of cardiovascular morbidity, avoidable hospitalisations, and premature death.

### 2.2.3 Fragmented Care Coordination

Effective management of a chronic condition like hypertension demands seamless coordination across multiple stakeholders: patients, physicians, pharmacists, and family members. However, the current care landscape is characterised by fragmentation across several distinct dimensions.

At the system level, there is no centralised national health record infrastructure in Malaysia; private hospitals maintain their own siloed patient management systems that do not interoperate with each other or with the public sector (Tee et al., 2025). Patients who receive care from multiple providers have no reliable mechanism to consolidate or share their health history, while healthcare providers must make clinical decisions with incomplete information.

At the communication level, patients, physicians, and pharmacists currently operate across entirely disconnected channels with no unified platform to support real-time communication, shared care planning, or coordinated clinical response. There is no structured mechanism for a patient to notify their physician of a concerning symptom between scheduled visits, nor for a physician to proactively reach out when monitoring data indicates deterioration.

At the social support level, family members, who play a critical and culturally expected role in chronic disease management in the Malaysian context, are entirely excluded from the current monitoring process and are typically involved only after a medical emergency has already occurred (WHO, 2023). Research has consistently demonstrated that family involvement improves medication adherence, appointment attendance, and chronic disease outcomes (Muehlensiepen et al., 2024), yet the current care model provides no mechanism to facilitate or formalise this involvement in day-to-day disease monitoring.

Taken together, these three dimensions of fragmentation, systemic, communicative, and social, are unlikely to be resolved by addressing any one of them in isolation. What they collectively point to is the need for a single integrated digital platform capable of consolidating patient records across providers, enabling real-time communication among all stakeholders in the care relationship, and formally incorporating family members into everyday monitoring rather than confining their involvement to emergencies.

##  

## 2.3 Mobile Health Applications for Hypertension Management

Mobile health (mHealth) applications have emerged as a promising intervention modality for chronic disease management, particularly for conditions like hypertension that require ongoing monitoring and adherence support. A randomised controlled trial investigating mHealth app-based interventions in hypertension patients found statistically significant improvements in patient health knowledge, medication adherence, physical activity, and blood pressure control relative to a control group receiving standard care (Liu et al., 2023). A broader scoping review of digital health implementations in chronic disease management confirmed that mHealth platforms show consistent potential for improving patient self-management and clinical outcomes across a range of chronic conditions (Pong et al., 2024).

Despite this evidence base, the majority of commercially available hypertension mHealth applications remain narrowly focused on basic self-monitoring functions, specifically blood pressure logging and trend visualisation. Critically, they fail to integrate the clinical intelligence, provider-facing tools, or care coordination capabilities that the limitations identified in Section 2.2 demand. This section critically reviews four of the most prominent existing hypertension management applications: Omron Connect, Withings Health Mate, SmartBP, and Cardi.Health. These four were selected because, together, they span the principal categories of hypertension mHealth tool currently on the market: proprietary hardware-companion applications tied to a specific manufacturer's Bluetooth devices (Omron Connect, Withings Health Mate); a hardware-agnostic, cross-platform logging tool accessible to any patient regardless of device brand (SmartBP); and a more clinically oriented application that incorporates personalised health insights and has itself been the subject of a published clinical evaluation (Cardi.Health, per Nakrys et al., 2023). This selection provides a representative cross-section of the current market, ranging from basic companion-logging tools to more sophisticated consumer health platforms, against which the gaps in current provision can be systematically identified. The review examines not only what each application offers but why its feature set falls short of addressing the clinical and operational gaps identified in the literature.

### 

### 2.3.1 Omron Connect

Omron Connect is a companion application developed by Omron Healthcare, one of the world's leading manufacturers of medical-grade blood pressure monitors, for use with their proprietary range of blood pressure monitoring devices. The application is available on both Android and iOS platforms and is designed to pair with Omron's Bluetooth-enabled blood pressure monitors to automatically sync readings to the mobile application without manual entry.

Omron Connect supports blood pressure logging and tracking, basic trend visualisation, and heart rate capture, though heart rate measurement requires the use of a dedicated Omron hardware device capable of measuring pulse and is not available through the smartphone alone. The application provides blood pressure history charts and allows users to share data via PDF export for clinical consultations. A notable feature is Omron's integration with Apple Health on iOS, which allows BP readings to be consolidated with data from other health applications.

Despite these capabilities, Omron Connect is designed exclusively for patient self-monitoring and provides no clinician portal, no healthcare provider access, and no remote monitoring capability. There is no medication management feature, no appointment scheduling, no symptom triage, no AI-powered risk prediction, no secure messaging between patients and providers, and no mechanism for family members to monitor the patient's condition (Lobo et al., 2023). The application addresses only the most basic layer of hypertension self-management and does not support any form of care coordination, clinical decision support, or AI-assisted health guidance. In summary, Omron Connect exemplifies the hardware-companion category of hypertension app: proficient at data capture and visualisation, but entirely absent of the clinical intelligence, provider connectivity, and care-coordination features that comprehensive hypertension management requires.

### 2.3.2 Withings Health Mate

Withings Health Mate is a health and wellness tracking platform developed by Withings, a French consumer health technology company, to accompany their range of connected health devices including blood pressure monitors, smartwatches, body composition scales, and sleep trackers. The application is available on both Android and iOS and is oriented toward a general wellness monitoring paradigm rather than condition-specific clinical management.

Withings Health Mate supports blood pressure logging and tracking, blood pressure trend visualisation, and heart rate monitoring, though heart rate capture is dependent on proprietary Withings hardware and is not available to users without the corresponding device. The application provides a multi-metric health dashboard that consolidates data from the full range of Withings devices, and includes a clinician-shareable health report export function. Withings has invested in improving the visual quality of its health data presentation, with clean, consumer-oriented chart interfaces.

However, Withings Health Mate does not include a clinician portal, provider-facing dashboard, or any mechanism for remote patient monitoring by healthcare teams. There is no machine learning risk prediction, no AI health agent, no symptom checker, no encrypted patient-doctor messaging, no NLP-based message escalation, no medication management module, no recurring prescription or delivery workflow, no family monitoring feature, and no emergency GPS alert capability (Lobo et al., 2023). The application functions as a consumer self-monitoring tool and does not address the clinical coordination or intelligent monitoring gaps identified in the literature. In summary, while Withings Health Mate offers a polished, multi-metric wellness experience, its contribution to hypertension management stops at self-monitoring: the clinical coordination, predictive risk assessment, and family-support gaps identified in Section 2.2 remain entirely unaddressed.

### 2.3.3 SmartBP Blood Pressure Monitor

SmartBP is a cross-platform blood pressure management application available on both Android and iOS, developed as a standalone software solution that does not require any proprietary hardware device. SmartBP supports both manual blood pressure entry from any conventional blood pressure cuff and optional Bluetooth synchronisation with a range of third-party Bluetooth-enabled BP monitors. This hardware-agnostic design makes SmartBP accessible to any patient with a standard smartphone, regardless of device brand, distinguishing it from companion applications such as Omron Connect and Withings Health Mate.

The application supports manual BP entry, blood pressure trend charts across multiple timeframes, statistical summaries including average, minimum, and maximum readings, a medication reminder feature, and health report generation in PDF format that can be shared with a healthcare provider. SmartBP also integrates with Apple Health on iOS and Google Fit on Android, allowing BP readings to be consolidated with data from other health applications. Users can tag readings with contextual notes such as activity level or emotional state, enabling richer self-monitoring. SmartBP has been cited in mHealth literature as an example of a hardware-independent blood pressure tracking tool accessible to a broad patient population (Wang et al., 2024).

Despite its accessibility and cross-platform availability, SmartBP lacks the clinical depth required for comprehensive hypertension management. There is no clinician portal, no healthcare provider dashboard, no AI-powered risk prediction, no secure patient-doctor messaging, no symptom triage engine, no NLP escalation, no family monitoring, and no emergency alert capability. Its medication reminder feature is basic and does not include adherence rate tracking, dose logging, recurring prescription workflow, or pharmacist integration. The health report export, while useful as a communication aid for clinic visits, does not replace a real-time provider-facing monitoring dashboard. SmartBP addresses only the data capture and visualisation layer of hypertension management and does not support multi-stakeholder care coordination or clinical decision support.

### 2.3.4 Cardi.Health

Cardi.Health is a digital health application focused on cardiovascular risk management, offering a more clinically oriented feature set than general-purpose blood pressure logging tools. The application has been subject to a published retrospective chart review study evaluating its effectiveness in supporting blood pressure control in a real-world patient cohort (Nakrys et al., 2023). The study reported that patients who used Cardi.Health over a twelve-week period demonstrated statistically significant reductions in average systolic blood pressure compared to baseline.

Cardi.Health includes blood pressure logging, basic trend visualisation, lifestyle tracking, medication reminders, and some degree of personalised health insight generation based on recorded readings. It also includes a heart rate monitoring feature and offers some AI-generated health feedback based on user inputs. The application is more sophisticated than Omron Connect or Withings Health Mate in terms of its health guidance capabilities.

It is important, however, to be precise about what "AI-generated" means in this context. The personalised feedback Cardi.Health provides appears to be produced through rule-based or heuristic logic rather than a trained, statistically validated machine learning model. A rule-based system applies a fixed set of pre-written if-then conditions (for example, "if systolic reading exceeds X, display message Y") authored in advance by a developer; it does not learn patterns from data, cannot improve its predictions as more data becomes available, and produces no measurable predictive accuracy metric such as an AUC-ROC score. A genuine machine learning risk-prediction model, by contrast, is trained on a labelled clinical dataset to statistically infer the relationship between a patient's input features and a specific health outcome, and its performance can be quantified and validated against a held-out test set (see the distinction elaborated further in Section 2.5.3). Cardi.Health does not publish a model architecture, training dataset, or validation performance for its personalisation feature, and there is no evidence in the literature of a validated multi-complication predictive engine within the application. The characterisation of Cardi.Health as offering "AI-generated" feedback should therefore be understood as algorithmic content personalisation rather than machine learning-based clinical risk stratification.

However, Cardi.Health does not provide a dedicated clinician portal or healthcare provider dashboard for remote patient monitoring. There is no secure encrypted messaging channel between patients and providers, no NLP-based message escalation, no recurring prescription and delivery workflow, no family monitoring capability, and no emergency GPS alert functionality. Its machine learning capability, while present in a limited form for personalized recommendations, does not extend to simultaneous multi-complication risk prediction across multiple disease outcomes. Cardi.Health represents an advancement over basic logging tools but remains oriented toward patient self-management rather than the multi-stakeholder, clinician-connected model required for comprehensive hypertension care coordination.

### 2.3.5 Comparative Feature Analysis

The table below summarises the feature comparison across the four reviewed systems and the proposed Hypertension Care Management Platform across eighteen dimensions of clinical and operational capability. The comparison is a synthesis constructed by the researcher, drawing on the individual application reviews presented in Sections 2.3.1 to 2.3.4, the published literature evaluating these applications (Lobo et al., 2023; Nakrys et al., 2023), and direct examination of each application's publicly documented feature set and app store listings. The "proposed platform" column reflects the planned feature set of the Hypertension Care Management Platform, detailed in Section 2.6 of this chapter.

| **Feature / Capability**                   | **Omron Connect** | **Withings Health Mate** | **SmartBP** | **Cardi.Health** |
|--------------------------------------------|-------------------|--------------------------|-------------|------------------|
| BP Logging & Tracking                      | YES               | YES                      | YES         | YES              |
| BP Trend Visualisation (7/30/90/365-day)   | YES               | YES                      | YES (basic) | YES              |
| Heart Rate Capture                         | Hardware req.     | Hardware req.            | NO          | YES              |
| No Hardware Required for HR                | NO                | NO                       | N/A         | YES              |
| ML Risk Prediction (5 complications)       | NO                | NO                       | NO          | NO               |
| AI Health Agent / Chatbot                  | NO                | NO                       | NO          | Partial          |
| Symptom Checker & Clinical Triage          | NO                | NO                       | NO          | NO               |
| Healthcare Provider Portal                 | NO                | NO                       | NO          | NO               |
| Encrypted Patient-Doctor Messaging         | NO                | NO                       | NO          | NO               |
| NLP Urgent Message Escalation              | NO                | NO                       | NO          | NO               |
| Medication Management (reminders, logging) | NO                | NO                       | Basic       | Basic            |
| Recurring Prescription & Home Delivery     | NO                | NO                       | NO          | NO               |
| Family Monitoring & Emergency GPS Alerts   | NO                | NO                       | NO          | NO               |
| Appointment Scheduling                     | NO                | NO                       | NO          | NO               |
| Admin Panel & Pharmacist Module            | NO                | NO                       | NO          | NO               |
| Multi-Stakeholder Role-Based Access        | NO                | NO                       | NO          | NO               |
| AI-Prioritised Provider Dashboard          | NO                | NO                       | NO          | NO               |
| 30-Day Deterioration Alert to Doctor       | NO                | NO                       | NO          | NO               |

*Table 2.3.5.1: Feature comparison of existing hypertension management systems against the proposed platform (source: researcher's synthesis of Sections 2.3.1–2.3.4, Lobo et al., 2023, and Nakrys et al., 2023)*

The comparison reveals a consistent and significant pattern across all four reviewed applications: existing systems address only the basic data capture and visualisation layer of hypertension management. None of the four applications provide a clinician portal, multi-stakeholder care coordination, AI-powered multi-complication risk prediction, encrypted patient-doctor messaging with intelligent escalation, family monitoring with emergency alerts, or an end-to-end recurring medication delivery workflow. These absences collectively constitute the research and design gaps that motivate the development of a more comprehensive platform.

Each absence identified in Table 2.3.5.1 maps directly onto a corresponding module of the proposed platform: the missing Healthcare Provider Portal is addressed by the platform's web-based clinician dashboard; the absence of ML risk prediction is addressed by the five-complication Random Forest/XGBoost engine described in Section 2.6.3; the lack of encrypted messaging and NLP escalation is addressed by the Care Coordination and Messaging module described in Section 2.6.6; the absence of family monitoring is addressed by the Family Monitoring and Emergency Alert feature; and the absence of a recurring medication and delivery workflow is addressed by the Stripe- and Grab-integrated medication module described in Section 2.6.7. This mapping between identified gap and platform response is discussed further, alongside the limitations of the underlying research base, in the dedicated Research Gap section that follows.

##  

## 2.4 Research Gap

The preceding sections collectively expose a set of research gaps that neither the academic literature on hypertension management nor the commercial mHealth applications currently on the market have adequately resolved. This section summarises those gaps and states explicitly how the proposed Hypertension Care Management Platform is designed to address each of them.

**Gap 1: Monitoring research is descriptive rather than interventional.** The literature reviewed in Sections 2.1 and 2.2.1 establishes, with strong epidemiological evidence, that clinic-centric monitoring leaves masked hypertension and inter-visit deterioration undetected (Nakrys et al., 2023; WHO, 2023). However, this body of research is almost entirely descriptive: it quantifies the scale of the monitoring gap without evaluating a deployed system that closes it through continuous, patient-generated data feeding into a provider-facing alerting mechanism. Lobo et al. (2023) explicitly note the absence of applications combining wearable or self-monitoring data with a clinician portal. The proposed platform addresses this gap directly through its Patient Monitoring module, which streams blood pressure readings into a web-based clinician dashboard with automated 30-day deterioration alerts (Section 2.6).

**Gap 2: Adherence research quantifies the problem but does not test a digital remedy.** The Malaysian and international medication-adherence literature (Lee et al., 2022; Ramli et al., 2012; Suleiman et al., 2024) is dominated by cross-sectional, survey-based studies that measure adherence rates and identify demographic predictors of non-adherence. This research does not evaluate an integrated intervention that combines reminders, adherence-rate tracking, and automatic escalation to a care team when adherence deteriorates. The proposed platform's Medication Management module is designed to close this gap by logging every dose event, computing a live adherence rate, and linking that rate to the provider dashboard and recurring prescription workflow (Sections 2.6.7).

**Gap 3: Existing mHealth applications are confined to the data-capture layer.** As demonstrated in the comparative analysis in Section 2.3.5, all four reviewed commercial applications, spanning both hardware-companion tools and more clinically oriented platforms, are limited to blood pressure logging, trend visualisation, and, at most, basic medication reminders. None provide a clinician portal, encrypted multi-stakeholder messaging, family monitoring, or a recurring medication delivery workflow. This is not a limitation specific to any one vendor but a structural gap across the entire commercial mHealth category for hypertension. The proposed platform's thirteen-module architecture is designed specifically to close this multi-dimensional gap in a single, integrated system rather than through a further isolated point solution.

**Gap 4: Machine learning risk prediction for hypertension complications remains confined to retrospective research and has not been operationalised in a deployed clinical tool.** The comparative technology review in Section 2.5.3 confirms that none of the four reviewed applications incorporate a validated predictive model, and Cardi.Health's "AI-generated" feedback is rule-based rather than statistically trained (Section 2.3.4). Meanwhile, the broader machine learning literature (Wu et al., 2024; Abramowitz et al., 2023) demonstrates that ensemble methods such as Random Forest and XGBoost can achieve strong predictive performance for cardiovascular complications, but these models are typically developed and validated in an offline research setting rather than deployed as a live, multi-complication risk engine accessible to both patients and clinicians in real time. The proposed platform's Machine Learning Disease Risk Prediction engine, detailed in Section 2.6.3, is designed to translate this research-stage capability into an operational component that generates simultaneous risk scores across five complications from a single patient input vector.

**Gap 5: Family involvement is well-evidenced as beneficial but is structurally excluded from existing digital tools.** Section 2.2.3 establishes that family involvement improves adherence and outcomes in the Malaysian context (Muehlensiepen et al., 2024), yet none of the four reviewed applications, nor the wider literature reviewed, offer any mechanism for formalising this involvement digitally. The proposed platform's Family Monitoring and Emergency Alert feature is designed specifically to close this gap by giving linked family members real-time visibility of a patient's readings and automated emergency notification.

Table 2.4.1 summarises this mapping between identified research gap, the corresponding limitation in the existing literature or commercial landscape, and the platform response.

| **Research Gap**                        | **Limitation in Existing Literature/Systems**                                                                             | **Platform Response**                                                                        |
|-----------------------------------------|---------------------------------------------------------------------------------------------------------------------------|----------------------------------------------------------------------------------------------|
| Reactive, episodic monitoring           | Descriptive studies only; no deployed continuous-monitoring-with-alerting system (Lobo et al., 2023)                      | Patient Monitoring module with 30-day deterioration alerts to the Healthcare Provider Portal |
| Medication non-adherence                | Survey-based prevalence studies without a tested digital intervention (Ramli et al., 2012; Suleiman et al., 2024)         | Medication Management module with adherence-rate tracking and provider escalation            |
| Data-capture-only mHealth apps          | All four reviewed apps limited to logging/visualisation/basic reminders (Section 2.3.5)                                   | Thirteen-module integrated platform spanning monitoring, AI, coordination, and delivery      |
| ML risk prediction confined to research | No validated multi-complication predictor in any reviewed app; Cardi.Health uses rule-based logic, not ML (Section 2.3.4) | Random Forest/XGBoost engine predicting five complications in parallel (Section 2.6.3)       |
| Family exclusion from monitoring        | No family-facing feature in any reviewed app despite evidence of benefit (Muehlensiepen et al., 2024)                     | Family Monitoring and Emergency GPS Alert feature                                            |

*Table 2.4.1: Summary mapping of identified research gaps to platform response*

## 2.5 Technologies Used in Existing Hypertension Management Systems

A review of the technologies underpinning existing hypertension management applications reveals a relatively narrow and consistent technology stack across the market. Understanding the current technological landscape provides important context for the technology selections made in the design of the proposed platform.

### 2.5.1 Mobile Development Frameworks

Existing consumer hypertension applications are predominantly developed using platform-native or cross-platform development frameworks. Omron Connect and Withings Health Mate maintain separate native iOS and Android codebases, developed in Swift and Kotlin respectively. This approach offers optimal platform-specific performance and full access to device APIs but introduces significant development overhead, as the same functionality must be implemented and maintained twice. SmartBP is developed as a cross-platform application available on both Android and iOS, leveraging shared business logic across platforms while maintaining native UI components for each operating system. Cardi.Health is developed using React Native, a cross-platform JavaScript framework that compiles to native components on both iOS and Android. The React Native approach reduces code duplication but introduces a JavaScript runtime layer that can reduce performance relative to fully native applications.

None of the reviewed applications use Flutter, Google's open-source cross-platform framework based on the Dart language. Flutter differs from React Native in that it compiles directly to native ARM code and renders UI elements through its own high-performance rendering engine (Skia/Impeller) rather than relying on platform-native components, offering performance characteristics closer to fully native applications while maintaining a single shared codebase across Android, iOS, and web deployments. An empirical benchmarking study comparing all three frameworks on Android, using profiling tools such as Android Studio's Profiler and Perfetto, found that Flutter consistently achieved the best performance due to its direct compilation to native code, while React Native offered the lowest learning curve for developers already familiar with JavaScript and Xamarin offered the simplest setup process within the Microsoft ecosystem (Mushtaq et al., 2024).

### 2.5.2 Backend and Database Technologies

Existing hypertension applications predominantly rely on proprietary cloud backends operated by their respective hardware manufacturers. Omron Connect synchronises data to Omron's proprietary cloud infrastructure, and Withings Health Mate stores data on Withings' servers, neither of which is interoperable with third-party systems or healthcare information systems. This proprietary model creates vendor lock-in and limits integration possibilities. SmartBP stores data on a cloud backend with optional local caching and integrates with Apple Health and Google Fit for cross-platform data consolidation, making it more interoperable than the proprietary hardware companion apps.

Cardi.Health employs a cloud-based backend, though the specific infrastructure is not publicly disclosed. None of the reviewed applications utilise Firebase, Google's real-time cloud database and authentication platform, which provides a managed, scalable infrastructure particularly well-suited to real-time health data synchronisation across multiple user roles and devices. Firebase's Cloud Firestore is documented as a NoSQL document database offering real-time listeners that notify connected clients immediately when underlying data changes, together with offline persistence and native integration with Firebase Authentication for enforcing role-based data access (Google, n.d.-a; Google, n.d.-b).

### 2.5.3 Machine Learning and AI

None of the four reviewed applications incorporate machine learning for predictive risk stratification in a clinically meaningful sense. Omron Connect and Withings Health Mate provide no AI or predictive capability beyond simple threshold alerts. SmartBP similarly provides no machine learning capability, relying entirely on rule-based threshold categorisation for its health status indicators.

For readers less familiar with these concepts, it is worth clarifying the distinction between rule-based AI and machine learning that recurs throughout this chapter. Rule-based systems operate on a fixed set of human-authored conditional rules (for example, "if systolic BP \> 140 mmHg for three consecutive days, display a warning"); they are transparent and easy to build, but they cannot improve with experience, cannot capture relationships between variables that a human designer did not anticipate, and their accuracy cannot be formally measured against a dataset because they do not make statistical predictions. Machine learning models, by contrast, are trained on historical, labelled data to statistically learn the relationship between a set of input features (for example, age, BMI, blood pressure history, smoking status) and an outcome (for example, five-year stroke risk); their predictive performance can be quantified using metrics such as AUC-ROC and validated against data the model has not seen during training. This distinction is central to evaluating the "AI" claims made by existing hypertension applications: an application that generates personalised messages from pre-written rules is not equivalent, in either capability or verifiability, to an application built on a trained and validated predictive model.

Cardi.Health provides limited personalised health feedback based on recorded readings. However, it is important to distinguish this from machine learning-based risk prediction: Cardi.Health's recommendations appear to be generated through rule-based logic or basic heuristics rather than a trained predictive model validated across multiple disease outcomes. The application does not publish model architecture, training data, or performance metrics, and there is no evidence in the literature of a validated multi-complication predictive engine within the application. The characterisation of Cardi.Health as offering "AI-generated" feedback therefore refers to algorithmic content personalisation rather than statistical machine learning in the clinical risk stratification sense.

The broader digital health literature identifies Random Forest and XGBoost as the most commonly deployed and best-performing machine learning algorithms for cardiovascular risk prediction tasks, due to their ability to handle mixed data types, high performance on tabular clinical data, and resistance to overfitting (Wu et al., 2024). Large language models, particularly Google's Gemini family, are increasingly being integrated into health applications for natural language interaction, patient education, and context-aware health guidance (Nozato & Yamamoto, 2024).

### 2.5.4 Communication and Notification Technologies

Communication features in existing hypertension applications are limited. None of the four reviewed systems provide secure end-to-end encrypted messaging between patients and healthcare providers. Notification delivery is typically handled through native mobile push notification frameworks (APNs for iOS, FCM for Android) for medication reminders and basic alerts. None of the reviewed systems implement NLP-based message scanning for urgent content detection or automated escalation. Emergency communication mechanisms, such as SMS alerting to family members or GPS location sharing, are absent from all reviewed platforms.

##  

## 2.6 Technologies Proposed for the Hypertension Care Management Platform

### 2.6.1 Flutter as the Cross-Platform Development Framework

The proposed platform adopts Flutter as the primary development framework. Flutter is an open-source UI toolkit developed and maintained by Google that enables the development of natively compiled applications for Android, iOS, and web from a single Dart codebase. Flutter's architecture is built around a proprietary rendering engine, originally Skia and now progressively migrating to the Impeller renderer, which draws every pixel of the UI directly rather than delegating to platform-native widgets. Google's official documentation confirms that, as of recent stable releases, Impeller is the default rendering engine on iOS and on Android API 29 and above, and that its design objective is predictable frame performance achieved by precompiling shaders offline at build time rather than compiling them at runtime, which was the primary source of rendering "jank" under the legacy Skia pipeline (Google, n.d.-c). This approach produces highly consistent UI behaviour across platforms and eliminates the cross-platform inconsistencies inherent in frameworks that rely on native component bridges.

A direct comparison of the three leading cross-platform frameworks is presented below to justify the selection of Flutter for this project. The performance characteristics summarised in the comparison are consistent with the empirical benchmarking findings of Mushtaq et al. (2024), discussed in Section 2.5.1, which found Flutter to offer the strongest raw performance of the three frameworks on Android due to its direct compilation to native code.

| **Criterion**         | **Flutter**                           | **React Native**                 | **Xamarin**                    |
|-----------------------|---------------------------------------|----------------------------------|--------------------------------|
| Language              | Dart                                  | JavaScript / TypeScript          | C# (.NET)                      |
| Rendering approach    | Custom engine (Skia/Impeller)         | Native platform bridge           | Native platform bridge         |
| Performance           | Near-native (compiled to ARM)         | Good (JS bridge overhead)        | Good (JIT/AOT compiled)        |
| Code sharing          | Single codebase for Android, iOS, Web | Single codebase for Android, iOS | Partial (platform-specific UI) |
| Firebase integration  | Official first-party SDK              | Community SDK                    | Community SDK                  |
| Camera / PPG access   | Yes (camera plugin)                   | Yes (react-native-camera)        | Limited (platform-specific)    |
| Community & ecosystem | Large and growing                     | Large and mature                 | Declining (Microsoft)          |
| Web deployment        | Full web build support                | Limited (React Native Web)       | Limited                        |
| Hot reload            | YES                                   | YES                              | YES                            |

*Table 2.6.1.1: Comparison of cross-platform mobile development frameworks (Mushtaq et al., 2024; Google, n.d.-c)*

Flutter is selected over React Native due to its superior rendering performance, its first-party Firebase SDK integration, its full web build support (which is required for the Healthcare Provider Portal and Admin Panel web deployments), and its native camera plugin access required for the mobile camera PPG heart rate capture feature. Flutter is selected over Xamarin due to its substantially more active community, larger package ecosystem, and Google's continued investment in the platform. The Flutter framework's single codebase approach is particularly valuable in the context of a solo development project, where maintaining separate iOS and Android codebases would be prohibitively time-intensive.

### 

### 2.6.2 Firebase as the Backend and Database Platform

Firebase, Google's managed cloud platform, is selected as the backend infrastructure for the proposed platform, encompassing Firestore as the primary database, Firebase Authentication for role-based user management, and Firebase Storage for medical document handling.

Firestore is a NoSQL document database with real-time synchronisation capabilities, meaning that data changes propagate instantly to all connected clients without requiring polling. According to Firebase's official documentation, Firestore's real-time listeners notify a connected client with a data snapshot whenever the specific data it is listening to changes, and the platform additionally provides native offline persistence so that an app remains usable and later synchronises automatically when connectivity is restored (Google, n.d.-a). This real-time behaviour is essential for features such as family monitoring, where linked family members must receive immediate updates when a patient's blood pressure reading changes, and for the patient-doctor messaging module, where message delivery must be near-instantaneous. Firestore's flexible document schema accommodates the diverse and heterogeneous data structures required across the platform's thirteen modules, from blood pressure readings and medication schedules to health records and triage outcomes.

Firebase Authentication provides a managed authentication service with support for email/password, phone authentication, and federated identity providers, and integrates natively with Firestore's security rules to enforce role-based access control at the database level (Google, n.d.-b). This allows the platform to enforce data isolation between user roles, ensuring that patients can only access their own health data, doctors can only access data belonging to their assigned patients, and administrators retain full system visibility.

| **Criterion**    | **Firebase (Firestore)**          | **PostgreSQL (Supabase)**       | **MongoDB Atlas**          |
|------------------|-----------------------------------|---------------------------------|----------------------------|
| Data model       | NoSQL document                    | Relational (SQL)                | NoSQL document             |
| Real-time sync   | Native (WebSocket)                | Requires additional setup       | Change streams (complex)   |
| Auth integration | Native (Firebase Auth)            | Built-in (Supabase Auth)        | Requires third-party       |
| Flutter SDK      | Official first-party              | Community SDK                   | Community SDK              |
| Offline support  | Native offline persistence        | Manual implementation           | Limited                    |
| Scalability      | Fully managed, auto-scaling       | Managed but needs configuration | Managed, auto-scaling      |
| File storage     | Firebase Storage (integrated)     | Supabase Storage (integrated)   | GridFS (complex)           |
| Cost model       | Generous free tier; pay-as-you-go | Free tier; PostgreSQL pricing   | Free tier; cluster pricing |

*Table 2.6.2.1: Comparison of backend database platforms for mobile health applications (Google, n.d.-a, n.d.-b)*

Firebase is selected over PostgreSQL-based solutions such as Supabase due to its native real-time synchronisation, first-party Flutter SDK, and seamless integration between Firestore, Firebase Authentication, and Firebase Storage. While a relational database would offer stronger query capabilities for complex joins, the data access patterns of the proposed platform are predominantly document-oriented reads and writes, making the NoSQL document model appropriate. Firebase is selected over MongoDB Atlas due to its superior Flutter SDK support and its native authentication integration.

### 2.6.3 Machine Learning: Random Forest and XGBoost for Disease Risk Prediction

The Machine Learning Disease Risk Prediction engine is designed to predict patient risk across five hypertension-related complications: stroke, coronary artery disease, heart failure, chronic kidney disease, and type 2 diabetes. The architecture employs multiple independent binary classification models rather than a single multi-output model: one model is trained per disease outcome, each using twelve clinical and lifestyle input variables. This independent-model architecture is adopted because each complication has a distinct set of predictive feature relationships and may be best served by different model hyperparameters; combining all five outcomes into a single multi-output model would constrain each output to the same learned feature representations and may reduce per-complication predictive accuracy. The five models operate in parallel at inference time, simultaneously generating a risk score for each complication from a single patient input vector, and results are presented together in the platform's risk dashboard to give the clinician and patient a unified multi-complication risk profile.

Random Forest is an ensemble learning method that constructs a large number of decision trees during training and aggregates their predictions by majority vote (for classification) or averaging (for regression). Each tree in the forest is trained on a bootstrapped subset of the training data and considers only a random subset of features at each split, a technique known as feature bagging, which reduces the correlation between individual trees and improves generalisation. Random Forest is well-established in clinical risk prediction literature due to its robustness to missing data, its ability to model non-linear feature interactions, and its inherent resistance to overfitting.

XGBoost is a gradient boosting framework that builds an ensemble of decision trees sequentially, with each successive tree trained to correct the residual errors of the preceding ensemble. XGBoost incorporates L1 and L2 regularisation terms in its objective function to prevent overfitting and supports efficient parallel computation through a column-block data structure. A comparative review of machine learning models for cardiovascular risk prediction confirmed that ensemble methods, particularly XGBoost and Random Forest, consistently achieve superior predictive performance relative to logistic regression and support vector machine approaches on clinical tabular datasets (Wu et al., 2024). A further study demonstrated that machine learning models can enhance predictive power by detecting complex, non-linear interactions among co-occurring risk factors that are inaccessible to traditional linear regression models.

| **Criterion**                 | **Random Forest**  | **XGBoost**         | **Logistic Regression** | **SVM**               |
|-------------------------------|--------------------|---------------------|-------------------------|-----------------------|
| Model type                    | Ensemble (bagging) | Ensemble (boosting) | Linear model            | Kernel-based          |
| Non-linear relationships      | YES                | YES                 | NO                      | YES (with kernel)     |
| Handles missing data natively | YES                | YES                 | NO                      | NO                    |
| Feature importance output     | YES                | YES                 | Partial                 | NO                    |
| Regularisation                | Implicit (bagging) | Explicit (L1/L2)    | Explicit (L1/L2)        | Implicit (margin)     |
| Interpretability              | Moderate (SHAP)    | Moderate (SHAP)     | High                    | Low                   |
| Training speed                | Moderate           | Fast (parallelised) | Fast                    | Slow (large datasets) |
| AUC-ROC on clinical data      | High               | High                | Moderate                | Moderate-High         |
| Overfitting resistance        | High               | High (with tuning)  | Moderate                | Moderate              |

*Table 2.6.3.1: Comparison of machine learning algorithms for clinical risk prediction*

Both Random Forest and XGBoost are selected for inclusion in the prediction engine. The two models are trained independently on each of the five disease outcome datasets; final risk scores are derived from the model that achieves the higher AUC-ROC on validation data for each specific complication. This dual-algorithm approach provides model-level redundancy and allows the engine to leverage the complementary strengths of bagging and boosting methodologies. The target minimum AUC-ROC of 0.80 for each complication predictor is consistent with the performance thresholds reported in comparable clinical machine learning studies (Wu et al., 2024).

### 2.6.4 Mobile Camera Photoplethysmography (PPG) for Heart Rate Detection

Photoplethysmography (PPG) is a non-invasive optical technique for measuring volumetric changes in blood flow by detecting variations in the amount of light absorbed by tissue. In the clinical setting, PPG is the basis for pulse oximeters, which shine light through the fingertip to detect oxygen saturation and heart rate. Mobile camera PPG extends this principle to standard smartphone cameras: when a patient places their fingertip over the rear camera lens and flash, the camera captures changes in the RGB pixel intensities of the transmitted light as blood pulses through the capillaries of the fingertip with each heartbeat.

The technique isolates the green colour channel from the captured frames, as the green wavelength is the most sensitive to haemoglobin absorption and therefore produces the highest signal-to-noise ratio for blood volume detection. A peak detection algorithm is then applied to the resulting time-series signal to identify systolic peaks and calculate the inter-beat interval, from which heart rate in beats per minute is derived. Peak detection on smartphone-camera PPG signals is complicated by noise arising from fingertip movement, inconsistent pressure against the lens, and changing ambient light; Lomaliza and Park (2018) address this specific problem, proposing an improved peak detection technique for smartphone-based PPG heart rate monitoring that is robust to these real-world noise sources and reports a heart rate estimation error as low as under one beat per minute across a range of smartphone models. The proposed platform's PPG processing pipeline adopts this general peak detection approach, adapted to the green-channel signal extracted from the Flutter camera plugin.

A scoping review of the validity of contact-based smartphone PPG for resting heart rate measurement concluded that appropriately implemented smartphone camera PPG demonstrates acceptable agreement with electrocardiography measurements under controlled resting conditions, making it suitable for use as a supplementary monitoring input in non-clinical settings (Mather, 2024). A calibration method for smartphone camera PPG was further validated by Xuan et al. (2023), confirming the feasibility of the technique on standard consumer hardware.

The primary limitation of mobile camera PPG is its sensitivity to ambient lighting conditions, fingertip placement consistency, and the optical characteristics of individual smartphone cameras (Mather, 2024; Benezeth et al., 2023). The proposed platform presents PPG readings as supplementary data points within the triage engine rather than as medically certifiable measurements, and the platform's documentation explicitly notes that PPG-derived heart rate values should not be used for clinical decision-making independently of professional assessment.

### 2.6.5 Google Gemini Flash as the AI Health Agent

The proposed platform integrates Google Gemini Flash as the underlying model for the AI Health Agent, which provides patients with 24/7 context-aware health guidance through a conversational interface. Gemini Flash is a lightweight, high-throughput variant of Google's Gemini large language model family, optimised for low-latency response generation in production applications while maintaining strong natural language understanding and instruction-following capabilities.

The AI Health Agent is designed to provide context-aware responses grounded in the patient's live health data: blood pressure readings, ML disease risk scores, current medications, symptom history, and onboarding medical profile. This is achieved through a technique commonly referred to as context injection, in which relevant patient data is inserted into the model's system instruction or prompt before each query is sent to the API, so that the model's response is grounded in that specific patient's record rather than generic medical knowledge. Google's Gemini API natively supports this pattern through a dedicated system instruction field that is sent alongside the user's message and persists across the conversation, allowing the platform to inject an up-to-date summary of the patient's vitals, risk scores, and medication list into every request without requiring the patient to restate this information (Google, n.d.-d). This approach is a specific application of prompt engineering, the broader practice of structuring model instructions, context, and examples to reliably steer a large language model's output toward a desired format and content; in this platform's case, the prompt engineering task is to keep the injected clinical context current, concise enough to remain within the model's context window, and clearly separated from the patient's own conversational input so the model does not confuse system-provided data with user claims. This contextualised approach distinguishes the proposed implementation from generic health chatbots that operate without access to individual patient data. The agent is capable of explaining ML risk scores in plain language, answering medication queries, providing lifestyle guidance aligned with the patient's risk level, and delivering proactive health status updates after each vital entry (Nozato & Yamamoto, 2024).

Gemini Flash is selected over alternative large language model APIs, including OpenAI GPT-4o and Anthropic Claude, based on three criteria: its integration with the Google ecosystem (which also underpins Firebase and Google Maps, reducing the number of external vendor relationships), its low per-token cost suited to a high-frequency health guidance use case, and its support for system-level context injection which enables the patient health profile to be embedded in every query. The model is accessed via the Gemini API and is subject to Google's responsible AI usage policies, which include content safety filtering appropriate for a healthcare context.

### 2.6.6 NLP-Based Message Analysis for Urgent Escalation

The Care Coordination and Messaging module incorporates an NLP-based message analysis scanner designed to detect high-risk clinical keywords within patient-initiated messages and automatically escalate flagged communications as urgent to the assigned healthcare provider. This feature is motivated by research demonstrating that natural language processing applied to patient-initiated electronic health record messages can effectively identify patients with clinically urgent conditions that require timely clinical attention (Mermin-Bunnell et al., 2023).

The proposed implementation is motivated by research demonstrating that NLP applied to patient-initiated electronic health record messages can effectively identify patients with clinically urgent conditions requiring timely clinical attention. Mermin-Bunnell et al. (2023) demonstrated this in the context of COVID-19, where keyword-based message analysis enabled early identification of high-risk patients from unstructured patient communications. A complementary study by Timmons et al. (2023) validated automated keyword detection for urgent content in a mental health digital messaging platform, confirming that NLP-based escalation substantially reduces the time between patient communication and clinical response for urgent cases.

While these studies were conducted in COVID-19 and mental health contexts respectively, the underlying methodological principle that structured keyword detection applied to free-text patient messages can reliably surface clinically urgent communications is not domain-specific. The urgency signals relevant to hypertensive emergencies, such as chest pain, severe headache, sudden visual disturbance, and difficulty breathing, constitute a well-defined and relatively constrained clinical vocabulary. This makes a rule-based keyword lexicon particularly appropriate for the hypertension domain, where the vocabulary of acute deterioration is more predictable than in open-ended mental health conversations. The approach is therefore adapted from the established NLP escalation methodology rather than applied wholesale from a different clinical context.

### 2.6.7 Stripe Payment Gateway and Grab API for Medication Delivery

The Recurring Medication, Payment, and Delivery module integrates two third-party APIs: the Stripe payment gateway for processing medication payments, and the Grab API for dispatching home delivery of prepared prescriptions. Stripe is selected as the payment processing solution due to its comprehensive SDK support for Flutter applications, its sandbox testing environment that allows full payment workflow simulation without processing real transactions, its built-in support for recurring payment workflows, and its compliance with Payment Card Industry Data Security Standards (PCI DSS). The Stripe Checkout and Payment Intents APIs are used to handle the monthly medication payment confirmation flow (Stripe, n.d.).

Grab is selected as the delivery logistics partner due to its extensive geographic coverage across Malaysia, its developer-accessible Grab for Business API which supports programmatic dispatch of delivery orders, real-time delivery tracking via webhook updates, and its established presence in the Malaysian market (Grab, n.d.). The Grab API integration enables the platform to dispatch medication delivery requests directly from the pharmacist workflow, with real-time status updates propagated to the patient via push notifications at each stage of the delivery lifecycle.

##  

## 2.7 Feasibility Study

A structured feasibility assessment is conducted across five dimensions to evaluate the viability of the proposed Hypertension Care Management Platform prior to development. This assessment considers technical, economic, social, operational, and schedule feasibility.

### 2.7.1 Technical Feasibility

The proposed platform relies on a technology stack that is mature, well-documented, and supported by extensive developer communities. Flutter is a production-ready framework actively maintained by Google, with first-party packages for Firebase integration, camera access, Google Maps, and push notifications, all of which are requirements of the proposed system. Firebase provides a fully managed serverless backend infrastructure that eliminates the need for manual server provisioning and administration, which would be prohibitively complex for a solo developer project.

The machine learning components are implemented using Python with scikit-learn and XGBoost, both of which are industry-standard libraries with extensive documentation and active maintenance. The training datasets, including the Framingham Heart Study dataset and the Pima Indians Diabetes Database, are publicly available on Kaggle and have been widely used in published clinical machine learning research, confirming their suitability as training sources. The ML models served as a FastAPI endpoint, a Python framework well-suited to serving lightweight inference endpoints (FastAPI, n.d.).

Mobile camera PPG is an established technique with published validation literature (Lomaliza & Park, 2018; Mather, 2024; Benezeth et al., 2023), and Flutter's camera plugin provides the pixel-level access required for green channel PPG signal extraction. Third-party API integrations, including Stripe (Sandbox), Grab API (sandbox/test mode), Google Maps Platform, SendGrid, and Twilio, all provide well-documented developer SDKs and sandbox environments that allow full integration testing without incurring production costs or regulatory obligations.

The one area of technical uncertainty is the performance of the mobile camera PPG implementation across the range of Android device hardware profiles, as camera optical quality and frame rate consistency vary across manufacturers and device generations. This risk is mitigated by confining PPG readings to a supplementary triage input role rather than a primary diagnostic function, and by implementing robust error handling and user guidance within the PPG capture flow. Technical feasibility is assessed as HIGH.

### 2.7.2 Economic Feasibility

The proposed platform is developed as an academic Final Year Project with a zero-budget constraint. All technology components are either open source, free-tier SaaS platforms, or sandbox/test environments with no production costs. Flutter and Dart are open source and free. Firebase's Spark (free) tier provides 1 GB of Firestore storage, 10 GB of hosted content, and 50,000 Firestore reads per day, which is sufficient for development and testing purposes. The Stripe Sandbox environment supports unlimited test transactions without charge. The Google Maps Platform provides a \$200 monthly free credit, which is more than adequate for the testing volume of a development project. Google Gemini Flash API access is available on a free tier with rate limits sufficient for development usage. Twilio and SendGrid both offer free developer tiers with limited monthly send volumes appropriate for testing.

For a hypothetical production deployment scenario, the cost structure of the platform is commercially viable. Firebase billing scales with actual usage on a pay-as-you-go model, meaning that initial deployment costs are low and scale proportionally with user growth. The Stripe integration enables direct monetisation through medication payment processing, and the Grab partnership provides a logistics infrastructure without capital expenditure. Economic feasibility is assessed as HIGH for the academic development context.

### 2.7.3 Social Feasibility

The social feasibility of the proposed platform is strongly supported by existing research and contextual factors. Research has consistently demonstrated that mHealth applications for hypertension management improve patient engagement, medication adherence, blood pressure control, and health knowledge when designed with appropriate usability (Liu et al., 2023; Muehlensiepen et al., 2024). Smartphone penetration in Malaysia reached 97% as of 2024, with Android devices accounting for the majority of the market, confirming that the target patient population has the necessary device access (Statista, 2024).

A genuine social feasibility risk, however, is digital literacy among elderly hypertensive patients, a demographic that represents a substantial share of the platform's intended user base. A recent systematic review of digital health technology adoption among older adults with chronic diseases found that limited digital literacy, alongside physical and cognitive challenges, remains one of the most consistently reported barriers to adoption, while tailored training, accessible interface design, and endorsement from healthcare providers were identified as the strongest facilitators of uptake (Hepburn et al., 2025). This suggests that smartphone ownership alone, as reflected in the national penetration statistic above, is not sufficient evidence of readiness to use a clinically oriented application; older patients may own a smartphone but still struggle with an unfamiliar interface, multi-step workflows, or unfamiliar terminology. This risk is partly mitigated by the platform's AI Health Agent, which is designed to explain health information in plain language, and by the Family Monitoring feature, which allows an adult family member to assist an elderly patient with day-to-day use of the application. Nonetheless, this remains an area that should be explicitly tested during User Acceptance Testing with elderly participants, with attention to interface simplicity and onboarding support rather than assumed based on general smartphone adoption figures. The Family Monitoring and Emergency Alert feature is specifically designed to align with the Malaysian cultural context, in which family members play an active and expected role in the healthcare of relatives with chronic conditions. Family involvement has been shown to improve medication adherence, appointment attendance, and chronic disease outcomes (Muehlensiepen et al., 2024), and the platform's family monitoring feature formalises and supports this involvement through a digital infrastructure. The AI Health Agent provides 24/7 health guidance in plain language, lowering the barrier to health literacy for patients who may have limited medical knowledge. Social feasibility is assessed as HIGH, with the caveat noted above regarding digital literacy among elderly users.

### 2.7.4 Operational Feasibility

The platform is designed for deployment within a Malaysian private hospital setting, where patients already attend regular consultations and have an established relationship with a healthcare provider. The administrative and clinical workflows implemented in the platform, including appointment scheduling, prescription management, clinical note-writing, and patient list management, are aligned with the existing operational practices of a private outpatient clinic. The Admin Panel provides hospital administrators with the tools required to manage user accounts, monitor system health, and oversee medication delivery operations without requiring specialist technical knowledge.

The platform's role-based access control model, which assigns each user a clearly defined role with corresponding permissions and interfaces, minimises the learning curve for each user group. Healthcare providers interact with a web-based portal designed for clinical workflow, pharmacists interact with a focused medication preparation interface, and family members interact with a simplified monitoring dashboard. User Acceptance Testing conducted with representative users from all five role groups will validate operational usability prior to final submission. Operational feasibility is assessed as HIGH.

### 2.7.5 Schedule Feasibility

The project is structured across a twenty-week timeline divided into six phases: requirements gathering and system planning (Weeks 1 to 9), Increment 1 covering core system and patient monitoring (Weeks 9 to 11), Increment 2 covering AI and clinical intelligence (Weeks 11 to 13), Increment 3 covering care coordination, medication, and extended features (Weeks 13 to 15), integration testing and refinement (Weeks 15 to 17), and documentation and submission (Weeks 17 to 20).

The Incremental Development methodology is specifically selected to manage schedule risk. Each increment produces a functional, independently testable subset of the complete system, meaning that development progress is demonstrable at each milestone without requiring the complete system to be operational. The allocation of development effort front-loads the foundational infrastructure (Firebase, Flutter project structure, authentication, database schema) in Increment 1, upon which all subsequent increments build. The most technically complex components, including the ML prediction engine and the camera PPG implementation, are scoped for Increment 2, which provides the developer with the foundation established in Increment 1 before approaching these challenges.

The principal schedule risk is scope creep arising from the breadth of the system: thirteen modules, four cross-cutting features, and five third-party API integrations represent a substantial development scope for a solo developer. This risk is mitigated by the out-of-scope exclusion of iOS deployment and production API integration (all third-party APIs are used in sandbox mode only), and by the modular architecture which allows lower-priority features to be descoped without breaking the core functionality of the system. Schedule feasibility is assessed as MODERATE to HIGH, acknowledging that disciplined scope management will be required throughout development.

| **Feasibility Dimension** | **Assessment** | **Rationale**                                                                                                                                                                             |
|---------------------------|----------------|-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Technical                 | HIGH           | Mature, well-documented technology stack; established ML and PPG techniques; full sandbox API support                                                                                     |
| Economic                  | HIGH           | Zero-cost academic development using free-tier platforms; commercially viable cost model for production                                                                                   |
| Social                    | HIGH           | Strong smartphone penetration; research-backed mHealth adoption; culturally aligned family monitoring feature; digital literacy among elderly users flagged as a risk to be tested in UAT |
| Operational               | HIGH           | Aligned with existing hospital workflows; role-based access minimises training burden; UAT validation planned                                                                             |
| Schedule                  | MODERATE-HIGH  | Broad scope managed through Incremental methodology; iOS and live APIs excluded to reduce complexity                                                                                      |

*Table 2.7.1: Summary of feasibility assessment across five dimensions*

##  

## 2.8 Chapter Summary

This chapter presented a comprehensive literature review covering the domain of hypertension management, existing digital health applications, the research and design gaps that motivate the proposed system, the technologies currently employed in the field, the technologies proposed for the Hypertension Care Management Platform, and a structured feasibility assessment.

Section 2.1 established the clinical and epidemiological context of hypertension, documenting its scale as a global and Malaysian public health challenge, its progressive organ-damaging mechanism, and the persistent diagnostic gap in Malaysia where undiagnosed hypertension has remained disproportionately high for over a decade.

Section 2.2 analysed the three core limitations of the current hypertension management landscape: the structural inadequacy of clinic-centric monitoring for a dynamic condition like hypertension, the globally and locally documented epidemic of anti-hypertensive medication non-adherence, and the fragmented care coordination environment that excludes family members and disconnects patients from their care teams between visits.

Section 2.3 reviewed four existing hypertension management applications, Omron Connect, Withings Health Mate, SmartBP, and Cardi.Health, through individual analysis and a comparative feature table across eighteen dimensions of clinical and operational capability. The review confirmed that all four systems address only the basic data capture and visualisation layer of hypertension management and none provide clinician portals, multi-complication AI risk prediction, encrypted patient-provider messaging, family monitoring, or end-to-end medication delivery workflows.

Section 2.4 introduced a dedicated Research Gap discussion, synthesising the limitations identified in Sections 2.1 to 2.3 into five specific gaps, spanning reactive monitoring, unaddressed medication non-adherence, data-capture-only commercial applications, research-stage-only machine learning risk prediction, and the digital exclusion of family caregivers, and explicitly mapping each gap to the corresponding module of the proposed platform.

Section 2.5 characterised the technologies currently used in existing hypertension applications, covering mobile development frameworks, backend and database technologies, machine learning and AI capabilities, and communication and notification technologies. This analysis identified the gaps in the current technology landscape that the proposed platform is designed to address.

Section 2.6 provided detailed literature-grounded justification for each of the core technology selections in the proposed platform: Flutter as the cross-platform development framework, Firebase as the backend and database platform, Random Forest and XGBoost as the machine learning algorithms for disease risk prediction, mobile camera PPG for hardware-independent heart rate detection, Google Gemini Flash as the AI Health Agent model, the NLP keyword detection approach for urgent message escalation, and Stripe and Grab as the payment and delivery infrastructure for the recurring medication workflow. Each technology was evaluated through a structured comparison against alternatives and justified based on the specific requirements of the proposed system.

Section 2.7 presented a five-dimension feasibility assessment covering technical, economic, social, operational, and schedule feasibility. Technical feasibility is HIGH based on the maturity of the technology stack and the availability of sandbox testing environments. Economic feasibility is HIGH for the academic development context given the availability of free-tier platforms. Social feasibility is HIGH based on smartphone penetration rates, research evidence for mHealth adoption, and the cultural alignment of the family monitoring feature with Malaysian healthcare norms, tempered by an acknowledged digital literacy risk among elderly users that will be assessed during User Acceptance Testing. Operational feasibility is HIGH given the alignment of platform workflows with existing private hospital practices. Schedule feasibility is assessed as MODERATE to HIGH, acknowledging the breadth of the development scope and the mitigation strategies implemented through the Incremental Development methodology and the exclusion of iOS and live API production deployments from project scope.

The next chapter will present the system requirements specification, covering functional and non-functional requirements for all five user roles, thirteen modules, and four cross-cutting features, together with the system architecture design, data model design, and UI/UX wireframes.

##  

## 2.9 References

Ab Majid, N. L., Mohd Yusoff, M. F., Abdullah, S., Musa, K. I., Yaacob, N. M., Mohamad, M. S., Sahril, N., & Aris, T. (2018). Prevalence, awareness, treatment and control of hypertension in Malaysia: Findings from the National Health and Morbidity Survey 2006–2015. *Journal of Human Hypertension*, *33*(2), 142–150. https://doi.org/10.1038/s41371-018-0082-x

Abramowitz, M. K., Hall, C. B., Amodu, A., Sharma, D., Androga, L., & Hawkins, M. (2023). The impact of non-adherence to antihypertensive drug therapy. *Pharmacy*, *11*(6), 177. https://doi.org/10.3390/pharmacy11060177

Benezeth, Y., Bobbia, S., Benoit, D., & Dubois, J. (2023). Remote photoplethysmography: Evaluation of contactless heart rate measurement in a realistic scenario. *Frontiers in Digital Health*, *5*, 1168336. https://doi.org/10.3389/fdgth.2023.1168336

FastAPI. (n.d.). *FastAPI documentation*. Retrieved July 6, 2026, from https://fastapi.tiangolo.com

Google. (n.d.-a). *Firestore documentation*. Firebase. Retrieved July 6, 2026, from https://firebase.google.com/docs/firestore

Google. (n.d.-b). *Firebase Authentication documentation*. Retrieved July 6, 2026, from https://firebase.google.com/docs/auth

Google. (n.d.-c). *Impeller rendering engine*. Flutter documentation. Retrieved July 6, 2026, from https://docs.flutter.dev/perf/impeller

Google. (n.d.-d). *Gemini API documentation*. Retrieved July 6, 2026, from https://ai.google.dev/gemini-api/docs

Grab. (n.d.). *Grab for Business API documentation*. Retrieved July 6, 2026, from https://developer.grab.com

Hepburn, J., Williams, L., & McCann, L. (2025). Barriers to and facilitators of digital health technology adoption among older adults with chronic diseases: Updated systematic review. *JMIR Aging*, *8*, e80000. https://doi.org/10.2196/80000

Ibrahim, N., Mohd Zaki, R., Che Roos, N. A., Shamsuddin, K., Jatau, A. I., & Awang Besar, J. (2022). The determinants of undiagnosed hypertension among urban community of Kuala Lumpur, Malaysia. *Iranian Journal of Public Health*, *51*(6), 1348–1358. https://doi.org/10.18502/ijph.v51i6.9914

Institute for Public Health, Ministry of Health Malaysia. (2024). *National Health and Morbidity Survey (NHMS) 2023: Non-communic+able diseases*. Ministry of Health Malaysia.

Lee, E. K. P., Poon, P., Yip, B. H. K., Bo, Y., Zhu, M.-T., Yu, C.-P., Ngai, A. C. H., Wong, M. C. S., & Wong, S. Y. S. (2022). Global burden, regional differences, trends, and health consequences of medication nonadherence for hypertension during 2010 to 2020: A meta-analysis involving 27 million patients. *Journal of the American Heart Association*, *11*(17), e026582. https://doi.org/10.1161/JAHA.122.026582

Liu, F., Song, T., Yu, P., Deng, N., Guan, Y., Yang, Y., & Ma, Y. (2023). Efficacy of an mHealth app to support patients' self-management of hypertension: Randomized controlled trial. *Journal of Medical Internet Research*, *25*, e43809. https://doi.org/10.2196/43809

Lobo, E. H., Karmakar, C., Abdelrazek, M., Abawajy, J., Chow, C. K., Zhang, Y., Kabir, M. A., Daryabeygi, R., Maddison, R., & Islam, S. M. S. (2023). Design and development of a smartphone app for hypertension management: An intervention mapping approach. *Frontiers in Public Health*, *11*, 1092755. https://doi.org/10.3389/fpubh.2023.1092755

Lomaliza, J. P., & Park, H. (2018). Improved peak detection technique for robust PPG-based heartrate monitoring system on smartphones. *Multimedia Tools and Applications*, *77*, 17131–17155. https://doi.org/10.1007/s11042-017-5282-9

Mather, J. D. (2024). Validity of resting heart rate derived from contact-based smartphone photoplethysmography compared with electrocardiography: A scoping review and checklist for optimal acquisition and reporting. *Frontiers in Digital Health*, *6*, 1326511. https://doi.org/10.3389/fdgth.2024.1326511

Mermin-Bunnell, K., Prabhu, A., Agurto, C., Bhatt, P., Bhatt, S., & Bhatt, V. (2023). Use of natural language processing of patient-initiated electronic health record messages to identify patients with COVID-19 infection. *JAMA Network Open*, *6*(6), e2317111. https://doi.org/10.1001/jamanetworkopen.2023.17111

Muehlensiepen, F., Bruch, D., Seifert, F., Wengemuth, E., Heinze, M., Spethmann, S., & May, S. (2024). mHealth apps for hypertension self-management: Interview study among patient-users. *JMIR Formative Research*, *8*, e56162. https://doi.org/10.2196/56162

Mushtaq, F., et al. (2024). Performance comparison of single code base development tools: Flutter, React Native, and Xamarin. In *2024 IEEE Conference Proceedings*. IEEE. https://doi.org/10.1109/ICSM.2024.10840376

Nakrys, M., Valinskas, S., Aleknavicius, K., & Jonusas, J. (2023). Pilot investigation of blood pressure control using a mobile app (Cardi.Health): Retrospective chart review study. *JMIR Cardio*, *7*, e48454. https://doi.org/10.2196/48454

Nozato, Y., & Yamamoto, K. (2024). The effects of smartphone apps expected in self-management for hypertension management. *Hypertension Research*, *47*, 1087–1089. https://doi.org/10.1038/s41440-023-01516-3

Pong, C., Tseng, R. M. W. W., Tham, Y. C., & Lum, E. (2024). Current implementation of digital health in chronic disease management: Scoping review. *Journal of Medical Internet Research*, *26*, e53576. https://doi.org/10.2196/53576

Ramli, A., Ahmad, N. S., & Paraidathathu, T. (2012). Medication adherence among hypertensive patients of primary health clinics in Malaysia. *Patient Preference and Adherence*, *6*, 613–622. https://doi.org/10.2147/PPA.S34704

Statista. (2024). *Smartphone penetration rate in Malaysia*. Retrieved from https://www.statista.com

Stripe. (n.d.). *Stripe API documentation*. Retrieved July 6, 2026, from https://docs.stripe.com

Suleiman, S. Z., Nu Nu Htay, M., Kyaw Soe, H. H., Low, L. Y. C., Alias, S. H., Yussof, S., Keng, W. X., Chong, K., Sahiran, M. F., Harun, M. H., Othman, A., Abdullah, R., Mohd Mansor, N., Ishak, N. H., Abdul Rahman, A. F. A., & Moe, S. (2024). Association between medication adherence and blood pressure control and factors associated with antihypertensive medication adherence in the Melaka Tengah District: A cross-sectional survey. *Malaysian Family Physician*, *19*, 56. https://doi.org/10.51866/oa.651

Tee, E. S., Chan, P., Lim, K. H., & Lim, K. K. (2025). The evolution of healthcare digitalisation policies in Malaysia: A four-decade narrative review (1985–2025). *Digital Health*, *11*. https://doi.org/10.1177/20552076251316502

Timmons, A. C., Duong, J. B., Fiallo, N. S., Lee, T., Vo, H. P. Q., Ahle, M. W., Comer, J. S., Brewer, L. C., Frazier, S. L., & Chaspari, T. (2023). Natural language processing system for rapid detection and intervention of mental health crisis chat messages. *npj Digital Medicine*, *6*, 220. https://doi.org/10.1038/s41746-023-00951-3

Wang, T., Huang, Y., & Chu, C. (2024). Exploration of features of mobile applications for medication adherence in Asia: Narrative review. *Journal of Medical Internet Research*, *26*, e60787. https://doi.org/10.2196/60787

World Health Organization. (2023). *Global report on hypertension: The race against a silent killer*. World Health Organization. https://www.who.int/publications/i/item/9789240081062

Wu, Y., Xin, B., Wan, Q., Ren, Y., & Jiang, W. (2024). Risk factors and prediction models for cardiovascular complications of hypertension in older adults with machine learning: A cross-sectional study. *Heliyon*, *10*(6), e27941. https://doi.org/10.1016/j.heliyon.2024.e27941

Xuan, Y., Duan, H., & Li, Q. (2023). A calibration method for smartphone camera photoplethysmography. *Frontiers in Digital Health*, *5*, 1301019. https://doi.org/10.3389/fdgth.2023.1301019
