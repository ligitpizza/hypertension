# **Chapter 3: Methodology and Requirement Analysis**

[Chapter 3: Methodology and Requirement Analysis](#chapter-3-methodology-and-requirement-analysis) 1

> [3.1 Incremental Development Model](#incremental-development-model) 1
>
> [3.1.1 Overview of the Model](#overview-of-the-model) 1
>
> [3.1.2 Phases Within Each Increment](#phases-within-each-increment) 1
>
> [3.1.3 Justification for Selection](#justification-for-selection) 2
>
> [3.2 Requirement Gathering Techniques](#requirement-gathering-techniques) 4
>
> [3.2.1 Interview question design](#interview-question-design) 4
>
> [3.2.2 Questionnaire question design](#questionnaire-question-design) 6
>
> [3.3 Requirement Analysis](#requirement-analysis) 8
>
> [3.3.1 Interview Findings](#interview-findings) 8
>
> [3.3.2 Questionnaire Findings](#questionnaire-findings) 13
>
> [likes](#likes) 23
>
> [Dislikes](#dislikes) 24
>
> [3.4 Use Case Diagram](#use-case-diagram) 36
>
> [3.5 Activity Diagram](#activity-diagram) 89
>
> [3.6 Functional Requirements](#functional-requirements) 104
>
> [3.7 Non-Functional Requirements](#_jzlxtewb7gc7) 110
>
> [3.8 Chapter Summary](#chapter-summary) 112
>
> [3.9 Reference](#reference) 114

##  

## **3.1 Incremental Development Model**

### **3.1.1 Overview of the Model**

This project adopts the Incremental Development model as its system development methodology. Under this model, the complete system is specified and architected upfront, but construction and delivery occur across a series of self-contained increments, each of which produces a functional, independently testable subset of the overall system. Each increment progresses through its own cycle of requirements analysis, design, implementation, and testing before the next increment begins, allowing the system to grow in functional capability while remaining verifiable at every stage rather than only at final delivery (Sommerville, 2016).

### **3.1.2 Phases Within Each Increment**

Requirements Analysis. At the start of each increment, the subset of functional and non-functional requirements allocated to that increment (see Section 3.6 and 3.7) is reviewed and, where necessary, refined based on findings from the requirement gathering activities in Section 3.2 and any lessons carried over from the previous increment.

Design. The modules assigned to the increment are designed in detail, covering UI/UX wireframes, Firestore data schema extensions, API contracts for any third-party integration introduced in that increment (e.g., the Gemini API in Increment 2, Stripe and Grab in Increment 3), and, where applicable, the use case and activity diagrams presented in Sections 3.4 and 3.5.

Implementation. The designed modules are built in Flutter (frontend) and FastAPI/Firebase (backend), following the module boundaries defined in the system architecture.

Testing. Each increment is unit- and integration-tested independently upon completion, verifying that the modules delivered in that increment function correctly both in isolation and against the increments already completed, before the next increment begins.

This four-step cycle is repeated across all three increments described in Section 1.9.2, followed by a system-wide integration testing and UAT phase (Phase 5) once all increments are complete.

##  

## **3.1.3 Justification for Selection**

The Incremental model was selected over three alternatives considered for this project.

The Waterfall model assumes requirements are fully stable before development begins and discourages revisiting earlier stages once passed. This assumption does not hold for a system of this complexity, where ML model integration, third-party API behaviour (Stripe, Grab, Gemini Flash), and camera PPG implementation are likely to require adjustment as development progresses and as findings from requirement analysis (Section 3.3) are validated against real implementation constraints (Royce, 1970; Sommerville, 2016).

The Prototyping model is best suited to projects where requirements are uncertain and must be discovered iteratively through user feedback on working prototypes. The requirements for this platform are already well-defined across five user roles, thirteen modules, and four cross-cutting features (Sections 3.4–3.7), making prototyping an ill-fitting justification for the primary methodology, though prototyping techniques (wireframing) are still used within the design phase of each increment (Sommerville, 2016).

Agile Scrum is designed around team-based ceremonies, sprint planning, daily standups, retrospectives, and a shared backlog that assume multiple contributors. Applied to a solo development context, these ceremonies introduce coordination overhead without a corresponding benefit, since there is no team to synchronise (Schwaber & Sutherland, 2020).

The Incremental model was therefore selected because it balances structured, auditable documentation (each increment has its own requirements, design, and test record) with development practicality for a solo developer, and because it allows high-priority, foundational modules (Increment 1) to be functional and testable early, reducing the risk of late-stage integration failure across the system's thirteen modules.

##  

## **3.2 Requirement Gathering Techniques**

Two complementary requirement gathering techniques were used: a semi-structured patient interview and a publicly distributed online questionnaire. The interview was used to gather depth directly, probing insight from a patient respondent describing their own day-to-day self-management experience while the questionnaire was used to gather breadth, validating and prioritising requirements across a much larger and more diverse respondent pool. Using both techniques allows the requirements in Section 3.3 to be triangulated from two different sources rather than relying on a single, narrow input.

### **3.2.1 Interview question design**

A semi-structured interview format was chosen over a fully structured one because it allows a consistent set of core questions to be asked while still allowing follow-up probing where the respondent raises an unanticipated point, rather than constraining the conversation to a rigid script (DeJonckheere & Vaughn, 2019).

The interview guide was designed around the hypertension patient, the platform's primary end user, since it is the patient's day-to-day self-management experience not a clinician's workflow that most directly motivates the platform's core, patient-facing modules (vital signs tracking, medication management, appointment scheduling). A parallel interview guide covering the doctor/clinician perspective was also drafted during the design process, but a clinician interview could not be arranged within the project's access constraints. This is noted explicitly as a limitation below.

**Patient Interview Guide**

The patient guide is structured into five sections, each targeting a specific category of requirement:

Background establishes the respondent's diagnosis context and comorbidities, which frames how their subsequent answers should be weighted (a newly diagnosed patient's challenges differ from a long-term patient's).

Current Monitoring & Medication Practices directly targets the behavioural pain points that justify the platform's core modules vital signs tracking, medication management, and appointment scheduling by asking how the patient currently manages these tasks without the system, establishing an "as-is" baseline before any feature is proposed.

Technology & App Experience assesses the respondent's existing familiarity with health apps and their baseline comfort with digital tools, which is necessary to judge whether a proposed feature is realistic for the target user rather than only appealing in the abstract.

Feature Feedback presents the platform's proposed modules (camera-based heart rate detection, the AI Health Agent, the symptom checker, secure doctor messaging) directly to the respondent and asks for a reaction, testing reception and surfacing trust concerns before development effort is committed to a feature.

Closing captures adoption barriers directly, asking what would make the respondent hesitant to use the platform, which is used to inform the non-functional requirements around trust, privacy, and usability (Section 3.6).

**Limitation: No Clinician Interview**

A doctor/clinician interview guide was drafted alongside the patient guide during the requirement gathering design process, intended to validate clinical-workflow assumptions behind the Healthcare Provider Portal (Module 8) and the alerting logic in Module 9. However, clinician access could not be secured within the project's timeframe, and no clinician interview was conducted. As a result, clinician-side requirements in this report are informed by the questionnaire's broader-population responses, secondary literature, and reasoned design assumptions, rather than by direct clinical validation. This is acknowledged as a limitation of the requirement analysis and is revisited in Chapter 5, where obtaining at least one clinician interview is recommended as a priority for any future iteration of this project.

###  

### **3.2.2 Questionnaire question design**

The questionnaire was distributed as a public online Google Form rather than restricted to confirmed patients, in order to capture both direct patient experience and broader public awareness and attitudes toward the platform concept reaching a sample size that would not have been feasible through interviews alone, and providing the quantitative feature-prioritisation data used in Section 3.3.

The form is structured into four sections, each with a distinct purpose:

Section 1: Demographics & Hypertension Status establishes respondent context (age group, diagnosis status, diagnosis duration, family history) before any platform-specific question is asked. Diagnosis duration uses a skip-if-not-applicable pattern so respondents who have not been diagnosed are not forced through an irrelevant follow-up, keeping the form quick to complete and reducing drop-off.

Section 2: Current Monitoring & Medication Habits gathers the same "as-is" behavioural baseline sought in the interviews, but across a much larger sample how often the respondent checks their blood pressure, whether they own home monitoring equipment, how often they forget or skip doses, and whether their family has experienced a hypertensive emergency. This section deliberately mirrors the interview's Current Practices section so that questionnaire responses can be used to validate or challenge patterns observed qualitatively in the interviews.

Section 3: Experience with Existing Health Apps benchmarks the platform's proposed value against current alternatives (e.g. Omron Connect, Apple Health, Google Fit), establishing whether existing solutions are meeting the need or whether there is a genuine adoption gap to address.

Section 4: Interest in Proposed Features asks respondents to rate each of the platform's nine core proposed features on a 1-to-5 usefulness scale, rather than a binary yes/no. A graded scale was chosen deliberately: a binary question can only confirm or reject a feature, whereas a 1-to-5 scale allows the features to be ranked against each other, which is necessary for the prioritisation and trade-off discussion in Section 3.3.4 when scope or timeline constraints require deciding which features matter most to users.

Most questions in the form use single-choice or multiple-choice formats to keep completion time short and response rate high; open-ended text questions were reserved for only three points in the form the biggest day-to-day challenge, current app likes/dislikes, and any other features or concerns where free-text nuance was judged more valuable than the completion-time cost of an open question. This balance between structured and open questions was itself refined iteratively during design; for example, an early draft of the "How often do you check your blood pressure?" The question mixed a location-based option ("Only at clinic or doctor visits") into what should have been a pure frequency scale, and was corrected before distribution to keep the ordinal logic (Never, Only at clinic, A few times a month, Weekly, Daily) consistent.

##  

##  

## **3.3 Requirement Analysis**

Interview and questionnaire data were analysed using two complementary approaches appropriate to their respective data types. Interview responses were analysed thematically: transcripts/notes were reviewed to identify recurring pain points, needs, and feature reactions, which were then grouped into themes and cross-referenced against the three problem domains defined in Section 1.3 (monitoring, adherence, coordination)(Braun & Clarke, 2006). Questionnaire responses were analysed descriptively, using frequency counts and percentages for each closed-ended item to identify the most commonly reported challenges and the most requested features. Together, these two analyses were used to confirm, adjust, and prioritise the module and feature set presented in Sections 3.4–3.6.

### **3.3.1 Interview Findings**


*Figure 3.1: Google Meet interview session conducted with Patient Daniel, 21 July 2026*

**Interview 1: Blood Pressure Patient Daniel**

Date: 21 July 2026 Method: Google Meet  
**Background:** Diagnosed with hypertension approximately 4 years ago during a routine company health screening. No other chronic conditions, though he noted a family history of diabetes (father), which he is mindful of.

**Monitoring behaviour  
**Daniel checks his blood pressure only once or twice a week at home, often prompted by memory or by feeling dizzy rather than a fixed routine. After taking a reading, he typically glances at the number and moves on, rarely logging it unless preparing for a clinic visit. He had previously tried Apple Health but stopped, saying it "didn't fit into his routine." He expressed interest in a camera-based heart rate feature but was clear that accuracy would need to be established before he would trust it.

**Medication adherence  
**The main obstacle to consistent medication is his work schedule remembering to take medication at the same time each day is difficult when his routine varies. He admitted to missing doses or scheduled checks, particularly while travelling or during busy work periods. When asked what would make adherence easier, he suggested reminders that adapt to his actual daily schedule rather than firing at a fixed time.

**Coordination with care providers  
**Daniel collects prescriptions from a private clinic near his office; his main pain point is occasional stock shortages requiring a return visit. He placed high importance on being able to message his doctor directly within an app, describing phone calls and hold times as "a hassle." He responded positively to the idea of an AI assistant explaining his readings in plain language, but stressed he would still want access to a real doctor for anything serious. Similarly, he said he would trust a symptom-checker feature more if it clearly stated it was not a replacement for a doctor and offered an easy way to reach one.

**Data privacy and trust  
**Trust in data handling underpinned several of his responses. He said he would be comfortable using a health app only if he understood where his data goes and who could see it, and identified data being sold or leaked as his main hesitation about adopting such an app. On family visibility, he wanted his spouse alerted only in a genuine emergency not given ongoing access to his everyday readings.

**Question:**

Could you tell me a bit about your diagnosis when you were diagnosed with hypertension, and how you manage it day to day?  
**Response:**

Diagnosed about 4 years ago during a routine company health screening. I take medication daily and try to watch my diet, but it's not always consistent.

**Question:**

Do you have any other chronic conditions (diabetes, kidney disease, heart disease) alongside your hypertension?  
**Response:  
** No other major conditions, but my father had diabetes, so I'm a bit worried about that too.

**Question:**

How often do you check your blood pressure, and where do you usually do it?  
**Response:**

I check maybe once or twice a week at home, sometimes only when I remember or when I feel dizzy.

**Question:**

Walk me through what you do after you take a reading.

**Response:  
** I just glance at the number and move on most of the time. I don't really write it down unless it's for a clinic visit.

**Question:**

What's the hardest part about sticking to your medication schedule?

**Response:  
** Remembering to take it at the same time every day changes my work schedule a lot so it's easy to forget.

**Question:**

Have you ever missed a dose or a scheduled check because you forgot, or because it was inconvenient?

**Response:  
** Yes, especially when travelling or during busy weeks at work.

**Question:**

How do you currently get your prescription refills? Any pain points there?

**Response:  
** I go to a private clinic near my office, it's usually fine but sometimes the medicine isn't in stock and I have to come back another day.

**Question:**

Do you currently use any app or device to track your health? What do you like or dislike about it?

**Response:  
** I tried Apple Health for a bit but stopped, it didn't really fit into my routine.

**Question:**

How comfortable are you with using a smartphone app for something as important as your health

data?  
**Response:**

I'd be okay with it as long as I understand where the data goes and who can see it.

**Question:**

Would you want a family member to see your readings or be alerted if something looks dangerous?  
**Response:**

I'd want my spouse to be alerted in an emergency, but not see my everyday readings that feels a bit too much.

**Question:**

Would a camera-based heart rate feature appeal to you? Would you trust it?  
**Response:**

That sounds useful, but I'd want to know how accurate it actually is before relying on it.

**Question:**

How would you feel about an AI assistant explaining your readings in plain language?  
**Response:**

I like the idea, but I'd still want to speak to a real doctor for anything serious.

**Question:**

Would you use a symptom checker that tells you whether to monitor at home, contact your doctor, or seek emergency care?  
**Response:**

I'd trust it more if it clearly said "this is not a replacement for a doctor" and gave me an easy way to contact one if needed.

**Question:**

How important is it to message your doctor directly through an app, versus calling or visiting the clinic?  
**Response:**

Quite important, calling the clinic and waiting on hold is a hassle.

**Question:**

What would make you hesitant to adopt an app like this?  
**Response:**

Mainly trusting that my health data is safe and not being sold or leaked somewhere.

**Question:**

Is there anything about managing your condition that we haven't talked about that you wish was easier?  
**Response:**

Maybe reminders that adjust based on my actual schedule instead of a fixed time.

###  

### **3.3.2 Questionnaire Findings**

This section analyses responses from the patient-facing questionnaire distributed as part of the requirement gathering process described in Section 3.2.2. Percentages are drawn directly from the Google Forms response summary. Where a finding suggests a design implication, this is stated as an assumption informing the functional requirements in Section 3.5.

**Section 1: Demographics & Hypertension Status**


*Figure 3.2: Survey responses – What is your age group? (n = 121)*

Respondents were fairly evenly spread across age brackets (21.5% under 25, 25.6% aged 25–39, 28.1% aged 40–59, and 24.8% aged 60 and above). This is notably younger than the typical hypertension patient population, which skews toward older adults; the questionnaire was distributed publicly rather than restricted to confirmed patients, so the sample captures general population awareness alongside patient experience. This is treated as a limitation in Section 3.3.5 and Chapter 5.


*Figure 3.3: Survey responses – Have you been diagnosed with hypertension? (n = 121)*


*Figure 3.4: Survey responses – If yes, how long have you been diagnosed? (n = 121)*

Only 31.4% of respondents confirmed a hypertension diagnosis, 33.1% reported no diagnosis, and 35.5% were not sure. This last figure is the largest single response and is treated as an assumption of a meaningful public awareness gap: over a third of respondents could not confidently state their own diagnosis status. This motivates the value of accessible, plain-language risk explanation (the AI Health Agent, FR-14.1) as a feature that benefits not only diagnosed patients but the broader at-risk population.


*Figure 3.5: Survey responses – Do you have a family history of hypertension or related conditions? (n = 121)*

Family history of hypertension or related conditions was reported by 33.9% of respondents, with 38.8% reporting no family history and 27.3% unsure. Combined with the diagnosis-awareness gap above, this supports prioritising early risk visibility features over assuming users already understand their own risk profile.

**Section 2: Current Monitoring & Medication Habits**


*Figure 3.6: Survey responses – How often do you check your blood pressure? (n = 121)*

Frequency of checking blood pressure produced the most decisive finding in the questionnaire: 31.4% of respondents the single largest group reported never checking their blood pressure, ahead of daily checkers (19.8%), monthly checkers (20.7%), weekly checkers (15.7%), and clinic-only checkers (12.4%). This is taken as direct evidence supporting the platform's core problem statement: poor self-monitoring habits are common even among a sample skewed toward a younger, more tech-comfortable demographic, reinforcing the need for low-friction logging and reminder mechanisms (Module 3, Module 5).


*Figure 3.7: Survey responses – Do you own a blood pressure monitor at home? (n = 121)*

Ownership of a home blood pressure monitor was almost evenly split (49.6% yes, 50.4% no). This is treated as an assumption supporting the value of the camera-based heart rate detection feature (FR-3.2): roughly half of respondents have no dedicated monitoring hardware, so device-free vital capture lowers the barrier to entry for this group.


*Figure 3.8: Survey responses – How often do you forget or skip a medication dose? (n = 120)*

Among respondents on blood pressure medication, 22.5% reported forgetting or skipping doses often (weekly or more) and a further 17.5% sometimes (a few times a month) a combined 40% reporting meaningful non-adherence. This is treated as strong support for the Medication Management module's reminder and missed-dose tracking functionality (FR-5.2, FR-5.3).


*Figure 3.9: Thematic breakdown of open-ended responses on the biggest day-to-day challenge of managing hypertension (n = 55)*

n = 55 open-ended responses

Time and schedule conflicts (most frequently cited theme, ~9 responses)  
The single largest cluster of responses centred on schedules clashing with health management. Respondents described clinic hours that only operate during their own work hours, night shifts and irregular rosters that make routine checks fall through the cracks, and travel that repeatedly disrupts established habits. Several framed it simply as struggling to juggle work, family, and health checks simultaneously. This directly supports the Adherence and Coordination problem domains reminders and appointment systems that assume a fixed 9-to-5 routine clearly don't fit a meaningful portion of this population.

Adherence and forgetfulness (~8 responses)  
A closely related cluster described the mechanics of forgetting: skipping doses while out of town, misplacing medication boxes or monitors while travelling, accidentally double-dosing because they couldn't recall whether they'd already taken it, losing track of which medicine to take when, and general memory lapses around appointments. Notably, a few mentioned that even family reminders (e.g., from their kids) weren't enough to fully solve this pointing to a need for system-level reminders, not just human ones.

Diet management (~8 responses)  
Diet challenges were almost entirely social/environmental rather than knowledge-based: respondents cited households where other family members don't eat the same restricted diet, in-laws or family who don't understand or respect dietary needs (causing friction at meals), the difficulty of finding low-sodium options when eating out, and the simple fact that local food culture is heavily salted. This suggests diet-tracking features alone are insufficient; the barrier is largely social/environmental, so household-inclusive or restaurant-navigation features may matter more than a logging tool.

Cost of medication (~4 responses)  
A smaller but consistent cluster flagged the ongoing financial burden of monthly medication, particularly when balanced against household expenses or compounded by other health conditions.

Clinic access friction (~6 responses)  
Distinct from scheduling, this theme covered the physical experience of getting to and through a clinic visit: traffic, lack of parking, long queues (especially at government clinics), language barriers with staff, long pharmacy wait times, and the practical issue of having no one available to accompany them. This is a clear Coordination pain point largely orthogonal to anything an app alone can fix, but relevant context for prioritising telehealth/messaging features over physical visits.

Monitoring device and accuracy concerns (~5 responses)  
Several respondents didn't trust their own data: uncertainty about whether home readings are accurate, monitors needing calibration they don't know how to do, inconsistent readings between attempts, an uncomfortable cuff discouraging use, and white coat syndrome inflating clinic readings. This is a direct, actionable Monitoring domain, finding it validates concerns raised in the Daniel interview about needing to trust a camera-based or app-based reading before relying on it.

Motivation, avoidance, and psychological barriers (~8 responses)  
The largest "soft" barrier cluster: laziness about checking despite known family risk, motivation fading after the initial diagnosis scare wore off, simply not feeling like measuring, forgetting the condition exists because they "feel fine," skipping checks on weekends, and notably anxiety about the reading itself leading to avoidance altogether. This is an important nuance: for some users, the barrier isn't forgetting, it's active avoidance, which reminders alone won't solve.

Stress as a contributing factor (2 responses)  
A couple of respondents noted that work stress and deadlines directly spike their BP less a "management challenge" than a trigger worth flagging for symptom-checking or educational content.

Comorbidity overwhelm, physical limitations, and misinformation (1–2 responses each)  
Isolated but notable mentions: managing hypertension on top of other chronic illnesses feels overwhelming; joint pain limits exercise options; and one respondent cited getting conflicting advice from different online sources, which is a small but relevant data point for the AI-assistant/symptom-checker feature discussed in the Daniel interview.


*Figure 3.10: Survey responses – Has a family member ever urgently needed to find out their blood pressure was dangerously high? (n = 121)*

33.9% of respondents reported a family incident where someone urgently needed to find out that their (or a relative's) blood pressure was dangerously high. This is treated as evidence that the Family Monitoring & Emergency Alert feature (FR-14.2) addresses a real, non-hypothetical scenario rather than a purely speculative use case.

**Section 3: Experience with Existing Health Apps**


*Figure 3.11: Survey responses – Do you currently use any app to track your blood pressure or health? (n = 121)*

47.1% of respondents currently use some form of health-tracking app, against 52.9% who do not. This roughly even split is treated as an assumption that there is substantial unmet demand: over half of respondents, despite the topic's relevance to them, have not adopted any existing solution, suggesting current tools are not sufficiently accessible, targeted, or trusted for this use case.


*Figure 3.12: Thematic breakdown of open-ended responses on current health-tracking methods used (n = 48)*

n = 48 responses

No dedicated tracking method (largest group, ~13 responses)  
A substantial portion of respondents use no app or system at all, relying instead on memory, verbal reporting to a nurse or pharmacist during appointments, or having the clinic/doctor keep the only record. Several were candid that this isn't a deliberate choice but a gap one respondent noted they'd "been meaning to download one but haven't gotten to it," and multiple others simply said their memory "isn't great." This is a significant finding: a meaningful share of the target population currently has zero digital or written record of their own readings between clinic visits, directly reinforcing the monitoring gap identified in the Daniel interview.

Manual/analog tracking (~6 responses)  
Rather than an app, some respondents keep their own informal system: writing readings down by hand, using a phone notes app, building a personal Google Sheets tracker, using a basic calculator app to compute averages, or maintaining a separate notebook alongside a diet-tracking app. One respondent specifically preferred an inherited paper-style BP diary over any app. This suggests demand exists for lightweight logging, but current solutions (existing apps) haven't met an opportunity for a genuinely simple logging flow.

Device-bundled apps (largest "active user" cluster, ~10 responses)  
Most respondents who do use an app are using whatever came bundled with their BP monitor or wearable, rather than a deliberately chosen platform: Omron Connect, iHealth, QardioArm, CareClinic, Zepp Health and Xiaomi Health (with fitness bands), Huawei Health, and Samsung Health or Apple Health/Fitbit syncing automatically from a smartwatch. Several admitted they don't check these regularly or don't even remember the app's name suggesting passive data collection without active engagement, which is a meaningful distinction from genuine app usage.

General fitness/wellness apps not built for BP (~5 responses)  
A number of respondents use apps for adjacent purposes Google Fit and Fitbit for steps, Cardiogram mainly for heart rate but noted these aren't really suited to blood pressure tracking specifically. Employer wellness apps, gym apps, insurance-provided health trackers, and MySejahtera were also mentioned as technically available but rarely or never used for BP.

Abandoned/churned app usage (~6 responses)  
Several respondents had tried a dedicated BP app and stopped: reasons included inconsistent use ("wasn't consistent with it"), trial periods ending (Renpho), excessive ads leading to deletion, being logged out repeatedly by a hospital-provided app, or simply uninstalling within a week. This churn pattern is directly relevant to your design considerations it points to specific failure modes (ads, login friction, lack of habit formation) worth explicitly avoiding.

Third-party/proxy tracking (~3 responses)  
A small but notable group has someone else manage their tracking rather than doing it themselves: a daughter who set up an app they rarely open, a husband who tracks readings on his own phone, and a brother who shares his own readings with them. This echoes the "family visibility" theme from the Daniel interview and suggests some users may want or already rely on a caregiver/family-linked tracking model rather than fully self-managed tracking.

Clinic/institutional portals (~2 responses)  
A couple of respondents mentioned their clinic's own patient portal has some tracking capability, though usage details weren't elaborated on.


*Figure 3.13: Thematic breakdown of open-ended responses on likes and dislikes of current health apps (n = 50)*

n = 50 responses

#### **likes**

Simplicity and minimalism (largest positive theme, ~9 responses)  
The most consistently praised quality was simplicity: respondents valued apps that offer basic logging without unnecessary complexity, no clutter, straightforward design that doesn't require fiddling with settings, and being "not overloaded with features I don't need." This is a strong signal that your feature set should default to a clean core experience, with advanced features (AI explanations, symptom checkers) layered optionally rather than front-and-centre.

Visual/trend features (~6 responses)  
Several liked simple line-graph trends, automatic categorisation of readings as normal/high/low, colour-coded high-reading alerts, and being able to view history over months to stay motivated. This validates that lightweight visualisation not necessarily complex analytics is genuinely valued.

Accessibility and performance (~7 responses)  
Positive mentions included dark mode for night-time use, working on a basic data plan, being lightweight enough not to lag on older phones, working across multiple devices, and syncing with a smartwatch. These point to real device-diversity constraints among your user base worth accounting for in technical requirements.

Cost and account friction (~4 responses)  
Respondents appreciated apps that are free without nagging upgrade prompts, don't require an account to use, and don't require an expensive companion device. This is a useful counterpoint to note against any premium/hardware-dependent feature you consider.

Customisation and reminders (~3 responses)  
A few liked being able to set their own target ranges, receive weekly summary emails, or get reminders though several of these came paired with a wish (see below) for the reminder to extend to family too.

#### **Dislikes**

Manual data entry burden (~2 responses, but reinforces earlier themes)  
Respondents disliked having to manually enter every reading themselves, tying directly back to the monitoring-friction theme from earlier questions reinforcing the case for automated/passive logging options.

Reliability and technical bugs (largest negative theme, ~9 responses)  
The most frequent complaints were technical: crashing (especially on chart pages), unreliable device syncing, duplicated entries, data disappearing after updates, and general instability. This is a clear signal that basic reliability matters more to users than advanced features; a buggy app undermines trust regardless of functionality.

Missing integration with doctors (~3 responses)  
Multiple respondents wished for direct report-sharing with their doctor, noted charts can't be shared directly, or wanted faster syncing with their doctor's system. This directly reinforces the Coordination domain and Daniel's stated preference for in-app doctor communication.

Poor customer support (~3 responses)  
Complaints included support only responding after several days or being "basically non-existent."

Monetisation friction (~3 responses)  
Constant upgrade-nagging notifications and excessive ads were called out as active irritants consistent with the earlier finding that ads were a reason some respondents abandoned apps entirely.

Usability gaps (~7 responses)  
Smaller but recurring complaints: inability to edit past entries, font too small, non-customisable charts, confusing data export, no voice input for hands-free logging, no medication reminder feature, complicated onboarding, and no side-by-side comparison of readings.

Battery drain (1 response)  
One respondent noted the app "drains my phone battery quite fast."

No smart/AI features (1 response)  
One respondent described their app as "pretty basic, no AI or smart features at all" a small but relevant data point given your project's proposed AI assistant feature.

**Section 4: Interest in Proposed Features**


*Figure 3.14: Survey responses – Interest in logging blood pressure readings and viewing trend charts (n = 121)*

*Figure 3.15: Survey responses – Interest in camera-based heart rate detection (n = 121)*


*Figure 3.16: Survey responses – Interest in AI-based prediction of complication risk (n = 121)*

*Figure 3.17: Survey responses – Interest in a 24/7 AI chat assistant (n = 121)*

*Figure 3.18: Survey responses – Interest in medication reminders and missed-dose tracking (n = 121)*

*Figure 3.19: Survey responses – Interest in automatic monthly medication refill and home delivery (n = 121)*


*Figure 3.20: Survey responses – Interest in secure messaging with a doctor (n = 121)*

*Figure 3.21: Survey responses – Interest in a symptom checker and triage feature (n = 121)*


*Figure 3.22: Survey responses – Interest in family monitoring and emergency alerts (n = 121)*

| Rank | Feature                                                          | rating 5 (Very useful) | Note                                                     |
|------|------------------------------------------------------------------|------------------------|----------------------------------------------------------|
| 1    | 24/7 AI chat assistant explaining health data                    | 48.8%                  | Highest-rated feature overall                            |
| 2    | Symptom checker & triage                                         | 47.9%                  | Near-tied for top interest                               |
| 3    | Family monitoring & emergency alert                              | 44.6%                  | Strong support for shared visibility                     |
| 4    | AI-based risk prediction (stroke, heart failure, kidney disease) | 43.0%                  | High trust in predictive guidance                        |
| 5    | Medication reminders & missed-dose tracking                      | 42.1%                  | Matches reported adherence gap                           |
| 6    | BP logging & trend charts                                        | 41.3%                  | Core monitoring feature, strong baseline interest        |
| 7    | Secure messaging with doctor                                     | 39.7%                  | Valued, though most polarised (19.8% rated 4, not 5)     |
| 8    | Automatic monthly refill & home delivery                         | 34.7%                  | Positive but the least differentiating logistics feature |
| 9    | Camera-based heart rate detection (PPG)                          | 33.9%                  | Lowest-rated of the nine, though still net-positive      |

The two highest-rated features the 24/7 AI chat assistant (48.8%) and the symptom checker & triage (47.9%) are both AI-driven decision-support tools rather than passive logging tools. This is treated as an assumption that respondents place a higher priority on features that actively interpret their health data and reduce uncertainty, rather than features that simply record it. This assumption is used to justify treating the AI Health Agent and Symptom Checker as core differentiators of the platform rather than secondary add-ons.

The lowest-rated feature, camera-based heart rate detection (33.9%), is still net-positive (a further 16.5% rated it 4), but its relative position at the bottom of the ranking is treated as an assumption that this feature, while a genuine technical differentiator, is not the primary driver of user interest. This is a relevant consideration if project scope needs to be reduced, though it is retained here given its role in enabling the device-free monitoring addressed in Section 3.3.2.


*Figure 3.23: Survey responses – Comfort with a family member seeing health readings in an emergency (n = 121)*

On data-sharing comfort, 47.1% of respondents said they would be comfortable with a family member seeing their health readings at all times, and a further 30.6% said only during emergencies a combined 77.7% comfortable with some level of family visibility. This is treated as validation for the configurable, tiered visibility approach already reflected in the Family Monitoring feature design, rather than an all-or-nothing sharing model.


*Figure 3.24: Survey responses – Would you use this app if your hospital or clinic offered it? (n = 121)*

On overall adoption intent, 38.8% of respondents said they would definitely use an app like this if their hospital or clinic offered it, and a further 35.5% said probably a combined 74.3% positive intent, against a small minority (combined approximately 12.5%) responding probably not or definitely not, and 13.2% not sure. This is treated as validation of the platform concept at a general level, while the not sure segment is noted as a group who may require clearer communication of the platform's clinical backing and data-privacy safeguards (NFR-8.1) to convert to adoption.


*Figure 3.25: Thematic breakdown of open-ended responses on additional feature requests and concerns (n = 52)*

n = 52 responses

**Feature Requests**

Family and caregiver integration (largest feature theme, ~8 responses)  
The most requested addition was extending the app beyond the individual user: alerting family during emergencies, reminders that also reach a caregiver's phone, multiple user profiles for the whole family, a family plan with multiple accounts, and multi-language support so family members can use it too. This strongly reinforces the family-visibility theme already seen in the Daniel interview and earlier questions a caregiver-linked account model appears to be a genuinely cross-cutting need, not a one-off preference.

Doctor/clinical integration (~4 responses)  
Requests included syncing directly with a clinic's system, exporting data directly to a clinic, consulting a doctor within the app itself, and printing reports for the doctor. This directly supports the Coordination domain and echoes Daniel's stated preference for in-app doctor communication over phone calls.

Localisation and accessibility (~7 responses)  
Respondents wanted a Bahasa Malaysia version, multi-language support, a simpler interface option for less tech-savvy users, better onboarding tutorials, ease of use for elderly parents, and support for visually impaired users. This is a significant finding accessibility isn't a fringe request but a recurring one, suggesting inclusive design should be a core requirement, not an afterthought.

Broader health tracking (~3 responses)  
Some wanted the app to track medication stock, blood sugar (not just BP), and support for people managing multiple chronic conditions simultaneously suggesting appetite for the app to grow beyond a single-condition tool over time, though this should be weighed carefully against the "keep it simple" preference from the previous question.

Government/system integration (~1-2 responses)  
A couple of respondents hoped for integration with government health initiatives like MySejahtera.

Alerts and notification flexibility (~3 responses)  
Requests included SMS alerts in addition to app notifications, control over notification frequency, and the ability to flag unusual patterns before they become serious (an early-warning feature).

Offline/low-resource functionality (~5 responses)  
A notable cluster wanted the app to work offline or without constant internet access, function on older phone models, offer a lightweight/lite version using less storage, and not require a new phone to run smoothly. Combined with an earlier finding (working on a basic data plan was already valued), this suggests your user base skews toward budget or older devices, which should inform technical requirements and testing.

Trial and support (~4 responses)  
Requests included a demo before committing, customer support if something goes wrong, a community support forum, and clearer/simpler terms and conditions.

Concerns

Data privacy and third-party sharing (largest concern theme, ~7 responses)  
This was the single biggest concern cluster: worry about data being used for marketing without consent, shared with insurance companies, accidentally shared with the wrong person, uncertainty over who else besides the doctor can see the data, and a general desire for data security and no leaks. This directly echoes Daniel's interview, where data privacy was also his primary hesitation; this concern now appears validated across the broader sample, not just an individual view.

Transparency about data handling (~4 responses)  
Related but distinct: respondents wanted clarity on how data is stored, how long it's retained, who develops/maintains the app, and clearer terms and conditions rather than legal jargon.

Long-term reliability of the service (~3 responses)  
Concerns included what happens if the company shuts down, long-term maintenance and updates, and what happens to personal data if the user stops using the app. This suggests users are thinking about data portability and continuity, not just immediate functionality.

Accuracy and trust in the technology (~3 responses)  
Concerns about accuracy of self-reported readings and how accurate AI predictions really are directly consistent with the accuracy/trust theme from the Daniel interview and the monitoring-device concerns raised earlier.

Cost (~2 responses)  
Worry about ongoing costs beyond a free trial.

Technical/compatibility concerns (~6 responses)  
Concerns about battery usage from background operation, needing constant internet access, compatibility with current phone OS, performance on older phone models, and reliability during emergencies when signal is poor this last one is particularly important given the app's safety-critical use case.

Data portability (~1 response)  
Wanting a backup option in case of switching phones.

## **3.4 Use Case Diagram**

The system involves five actors: Patient, Healthcare Provider (Doctor), Family Member, Pharmacist, and Admin. Use case diagrams were developed for each of the thirteen modules to define the interactions between these actors and the system. The use cases listed below form the basis for the UML use case diagrams.

**3.4.1 Module 1 User and Access Management**


*Figure 3.26: Use Case Diagram – Module 1: User and Access Management*

<table>
<colgroup>
<col style="width: 25%" />
<col style="width: 75%" />
</colgroup>
<thead>
<tr class="header">
<th>Use Case Name</th>
<th>UC1.1 Register Account</th>
</tr>
<tr class="odd">
<th>Brief Description</th>
<th>Creates a new self-service account for a Patient or Family Member, establishing the identity used for all subsequent role-scoped use cases. Doctor, Pharmacist, and Admin accounts are not created this way (see Create Staff Account, UC1.5).</th>
</tr>
<tr class="header">
<th>Characteristic of activation</th>
<th>Triggered when a Patient or Family Member submits the registration form.</th>
</tr>
<tr class="odd">
<th>Primary Actor</th>
<th>Patient, Family Member</th>
</tr>
<tr class="header">
<th>Secondary Actor</th>
<th>None</th>
</tr>
<tr class="odd">
<th>Pre-Condition(s)</th>
<th>The email/credentials used are not already associated with an existing account.</th>
</tr>
<tr class="header">
<th colspan="2">Flow of Event</th>
</tr>
<tr class="odd">
<th>Basic Flow</th>
<th><p>1. Patient or Family Member provides email, password, and name.</p>
<p>2. The system creates the record via Firebase Authentication.</p>
<p>3. The system creates a corresponding Firestore user document.</p>
<p>4. System assigns the Patient or Family Member role to the account.</p>
<p>5. The system directs the user to the role-appropriate entry point.</p></th>
</tr>
<tr class="header">
<th>Alternative Flow</th>
<th>A1: If the actor is a Patient, the system triggers Complete Onboarding Health Profile (UC1.4) immediately after account creation.</th>
</tr>
<tr class="odd">
<th>Exception Flow</th>
<th><p>E1: Email already registered system displays an error and prompts the user to log in instead.</p>
<p>E2: Password does not meet complexity requirements system rejects submission and shows validation guidance.</p></th>
</tr>
</thead>
<tbody>
</tbody>
</table>

<table>
<colgroup>
<col style="width: 25%" />
<col style="width: 75%" />
</colgroup>
<thead>
<tr class="header">
<th>Use Case Name</th>
<th>UC1.2 Log In</th>
</tr>
<tr class="odd">
<th>Brief Description</th>
<th>Authenticates a returning user of any role and restores their role-scoped session.</th>
</tr>
<tr class="header">
<th>Characteristic of activation</th>
<th>Triggered when a user submits login credentials.</th>
</tr>
<tr class="odd">
<th>Primary Actor</th>
<th>All roles (Patient, Doctor, Family Member, Pharmacist, Admin)</th>
</tr>
<tr class="header">
<th>Secondary Actor</th>
<th>None</th>
</tr>
<tr class="odd">
<th>Pre-Condition(s)</th>
<th>An account already exists for the credentials provided.</th>
</tr>
<tr class="header">
<th colspan="2">Flow of Event</th>
</tr>
<tr class="odd">
<th>Basic Flow</th>
<th><p>1. The user enters an email and password.</p>
<p>2. System validates credentials via Firebase Authentication.</p>
<p>3. The system retrieves the user's role and profile.</p>
<p>4. The system directs the user to their role-specific dashboard.</p></th>
</tr>
<tr class="header">
<th>Alternative Flow</th>
<th>A1: User selects "Forgot password" system, sends a password reset link and returns to the login screen.</th>
</tr>
<tr class="odd">
<th>Exception Flow</th>
<th><p>E1: Incorrect credentials system displays an error without indicating whether the email or password was wrong.</p>
<p>E2: Account deactivated by Admin system denies login and displays a contact-support message.</p></th>
</tr>
</thead>
<tbody>
</tbody>
</table>

<table>
<colgroup>
<col style="width: 25%" />
<col style="width: 75%" />
</colgroup>
<thead>
<tr class="header">
<th>Use Case Name</th>
<th>UC1.3 Log Out</th>
</tr>
<tr class="odd">
<th>Brief Description</th>
<th>Ends the user's authenticated session, regardless of role.</th>
</tr>
<tr class="header">
<th>Characteristic of activation</th>
<th>Triggered when the user selects Log Out.</th>
</tr>
<tr class="odd">
<th>Primary Actor</th>
<th>All roles (Patient, Doctor, Family Member, Pharmacist, Admin)</th>
</tr>
<tr class="header">
<th>Secondary Actor</th>
<th>None</th>
</tr>
<tr class="odd">
<th>Pre-Condition(s)</th>
<th>The user has an active session.</th>
</tr>
<tr class="header">
<th colspan="2">Flow of Event</th>
</tr>
<tr class="odd">
<th>Basic Flow</th>
<th><p>1. User selects Log Out.</p>
<p>2. The system invalidates the session token.</p>
<p>3. The system returns the user to the login screen.</p></th>
</tr>
<tr class="header">
<th>Alternative Flow</th>
<th>None.</th>
</tr>
<tr class="odd">
<th>Exception Flow</th>
<th>E1: Network interruption during logout system clears local session state regardless, to avoid an unlocked device remaining signed in.</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

<table>
<colgroup>
<col style="width: 25%" />
<col style="width: 75%" />
</colgroup>
<thead>
<tr class="header">
<th>Use Case Name</th>
<th>UC1.4 Complete Onboarding Health Profile</th>
</tr>
<tr class="odd">
<th>Brief Description</th>
<th>One-time intake of clinical and lifestyle data (medical history, lifestyle factors) for a newly registered patient. Extends Register Account (UC1.1); applies only to the Patient role, and only on first login.</th>
</tr>
<tr class="header">
<th>Characteristic of activation</th>
<th>Triggered automatically the first time a Patient account logs in after registration.</th>
</tr>
<tr class="odd">
<th>Primary Actor</th>
<th>Patient</th>
</tr>
<tr class="header">
<th>Secondary Actor</th>
<th>None</th>
</tr>
<tr class="odd">
<th>Pre-Condition(s)</th>
<th>The actor has just registered as a Patient and has not previously completed onboarding.</th>
</tr>
<tr class="header">
<th colspan="2">Flow of Event</th>
</tr>
<tr class="odd">
<th>Basic Flow</th>
<th><p>1. The system presents the onboarding form (personal information, medical history, lifestyle factors).</p>
<p>2. The patient completes each section.</p>
<p>3. The patient submits the form.</p>
<p>4. The system validates and stores the profile.</p>
<p>5. The system marks onboarding as complete and proceeds to the Patient dashboard.</p></th>
</tr>
<tr class="header">
<th>Alternative Flow</th>
<th>A1: Patient saves partial progress and resumes onboarding at next login.</th>
</tr>
<tr class="odd">
<th>Exception Flow</th>
<th>E1: Required field left blank system blocks submission and highlights missing fields.</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

<table>
<colgroup>
<col style="width: 25%" />
<col style="width: 75%" />
</colgroup>
<thead>
<tr class="header">
<th>Use Case Name</th>
<th>UC1.5 Create Staff Account</th>
</tr>
<tr class="odd">
<th>Brief Description</th>
<th>Allows the Admin to provision a new Doctor, Pharmacist, or Admin account on behalf of hospital staff, since these roles have no self-registration access of their own.</th>
</tr>
<tr class="header">
<th>Characteristic of activation</th>
<th>Triggered when the Admin submits the new staff account form.</th>
</tr>
<tr class="odd">
<th>Primary Actor</th>
<th>Admin</th>
</tr>
<tr class="header">
<th>Secondary Actor</th>
<th>None</th>
</tr>
<tr class="odd">
<th>Pre-Condition(s)</th>
<th>Admin is authenticated; the staff member's employment/role has been verified outside the system.</th>
</tr>
<tr class="header">
<th colspan="2">Flow of Event</th>
</tr>
<tr class="odd">
<th>Basic Flow</th>
<th><p>1. Admin opens the Create Staff Account screen.</p>
<p>2. Admin enters the staff member's name, email, and assigns a role (Doctor, Pharmacist, or Admin).</p>
<p>3. The system creates the account via Firebase Authentication.</p>
<p>4. The system creates a corresponding Firestore user document with the assigned role.</p>
<p>5. The system sends the new staff member their login credentials or a setup link.</p></th>
</tr>
<tr class="header">
<th>Alternative Flow</th>
<th>A1: Admin assigns a Doctor to specific patients as part of account setup.</th>
</tr>
<tr class="odd">
<th>Exception Flow</th>
<th>E1: Email already registered system displays an error and prevents duplicate account creation.</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

**3.4.2 Module 2 Patient Health Overview**


*Figure 3.27: Use Case Diagram – Module 2: Patient Health Overview*

<table>
<colgroup>
<col style="width: 25%" />
<col style="width: 75%" />
</colgroup>
<thead>
<tr class="header">
<th>Use Case Name</th>
<th>UC2.1 View Health Summary Dashboard</th>
</tr>
<tr class="odd">
<th>Brief Description</th>
<th>Displays a consolidated view of the patient's current status, composed of the medication schedule, upcoming appointments, and risk score card.</th>
</tr>
<tr class="header">
<th>Characteristic of activation</th>
<th>Triggered when the Patient opens the app or navigates to the dashboard.</th>
</tr>
<tr class="odd">
<th>Primary Actor</th>
<th>Patient</th>
</tr>
<tr class="header">
<th>Secondary Actor</th>
<th>None</th>
</tr>
<tr class="odd">
<th>Pre-Condition(s)</th>
<th>The patient has completed onboarding.</th>
</tr>
<tr class="header">
<th colspan="2">Flow of Event</th>
</tr>
<tr class="odd">
<th>Basic Flow</th>
<th><p>1. The patient opens the dashboard.</p>
<p>2. System retrieves and displays Medication Schedule (UC2.2), Upcoming Appointments (UC2.3), and Risk Score Card (UC2.4).</p></th>
</tr>
<tr class="header">
<th>Alternative Flow</th>
<th>None.</th>
</tr>
<tr class="odd">
<th>Exception Flow</th>
<th>E1: One or more data sources fail to load system displays the remaining sections and an inline error for the failed section.</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

<table>
<colgroup>
<col style="width: 25%" />
<col style="width: 75%" />
</colgroup>
<thead>
<tr class="header">
<th>Use Case Name</th>
<th>UC2.2 Medication Schedule</th>
</tr>
<tr class="odd">
<th>Brief Description</th>
<th>Shows the patient's medications due today. Includes into View Health Summary Dashboard (UC2.1); always shown as part of it.</th>
</tr>
<tr class="header">
<th>Characteristic of activation</th>
<th>Rendered automatically whenever the dashboard loads.</th>
</tr>
<tr class="odd">
<th>Primary Actor</th>
<th>Patient</th>
</tr>
<tr class="header">
<th>Secondary Actor</th>
<th>None</th>
</tr>
<tr class="odd">
<th>Pre-Condition(s)</th>
<th>At least one medication is on the patient's list (Module 5).</th>
</tr>
<tr class="header">
<th colspan="2">Flow of Event</th>
</tr>
<tr class="odd">
<th>Basic Flow</th>
<th><p>1. System retrieves today's scheduled doses from Module 5.</p>
<p>2. System renders them on the dashboard.</p></th>
</tr>
<tr class="header">
<th>Alternative Flow</th>
<th>None.</th>
</tr>
<tr class="odd">
<th>Exception Flow</th>
<th>E1: No medications on file system displays an empty state with a prompt to add one.</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

<table>
<colgroup>
<col style="width: 25%" />
<col style="width: 75%" />
</colgroup>
<thead>
<tr class="header">
<th>Use Case Name</th>
<th>UC2.3 Upcoming Appointments</th>
</tr>
<tr class="odd">
<th>Brief Description</th>
<th>Shows the patient's next scheduled appointments. Includes into View Health Summary Dashboard (UC2.1); always shown as part of it.</th>
</tr>
<tr class="header">
<th>Characteristic of activation</th>
<th>Rendered automatically whenever the dashboard loads.</th>
</tr>
<tr class="odd">
<th>Primary Actor</th>
<th>Patient</th>
</tr>
<tr class="header">
<th>Secondary Actor</th>
<th>None</th>
</tr>
<tr class="odd">
<th>Pre-Condition(s)</th>
<th>None (an empty list is a valid state).</th>
</tr>
<tr class="header">
<th colspan="2">Flow of Event</th>
</tr>
<tr class="odd">
<th>Basic Flow</th>
<th><p>1. System retrieves upcoming bookings from Module 7.</p>
<p>2. The system renders them on the dashboard.</p></th>
</tr>
<tr class="header">
<th>Alternative Flow</th>
<th>None.</th>
</tr>
<tr class="odd">
<th>Exception Flow</th>
<th>E1: No appointments booked system displays a prompt to book one.</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

<table>
<colgroup>
<col style="width: 25%" />
<col style="width: 75%" />
</colgroup>
<thead>
<tr class="header">
<th>Use Case Name</th>
<th>UC2.4 Risk Score Card</th>
</tr>
<tr class="odd">
<th>Brief Description</th>
<th>Shows the patient's current ML-predicted disease risk levels. Includes into View Health Summary Dashboard (UC2.1); always shown as part of it.</th>
</tr>
<tr class="header">
<th>Characteristic of activation</th>
<th>Rendered automatically whenever the dashboard loads.</th>
</tr>
<tr class="odd">
<th>Primary Actor</th>
<th>Patient</th>
</tr>
<tr class="header">
<th>Secondary Actor</th>
<th>System</th>
</tr>
<tr class="odd">
<th>Pre-Condition(s)</th>
<th>At least one risk score has been generated (Module 9, UC9.1).</th>
</tr>
<tr class="header">
<th colspan="2">Flow of Event</th>
</tr>
<tr class="odd">
<th>Basic Flow</th>
<th><p>1. The system retrieves the most recent risk scores.</p>
<p>2. System renders the risk level (Low/Moderate/High/Critical) per complication.</p></th>
</tr>
<tr class="header">
<th>Alternative Flow</th>
<th>None.</th>
</tr>
<tr class="odd">
<th>Exception Flow</th>
<th>E1: No risk score generated yet (e.g. no vitals logged) system displays a prompt to log a reading.</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

<table>
<colgroup>
<col style="width: 25%" />
<col style="width: 75%" />
</colgroup>
<thead>
<tr class="header">
<th>Use Case Name</th>
<th>UC2.5 Navigate to Key Modules</th>
</tr>
<tr class="odd">
<th>Brief Description</th>
<th>Provides shortcut navigation from the dashboard to Vitals, Symptom Checker, Messaging, and the AI Agent.</th>
</tr>
<tr class="header">
<th>Characteristic of activation</th>
<th>Triggered when the Patient taps a navigation shortcut.</th>
</tr>
<tr class="odd">
<th>Primary Actor</th>
<th>Patient</th>
</tr>
<tr class="header">
<th>Secondary Actor</th>
<th>None</th>
</tr>
<tr class="odd">
<th>Pre-Condition(s)</th>
<th>The patient is on the dashboard.</th>
</tr>
<tr class="header">
<th colspan="2">Flow of Event</th>
</tr>
<tr class="odd">
<th>Basic Flow</th>
<th><p>1. The patient taps a shortcut.</p>
<p>2. System routes to the corresponding module.</p></th>
</tr>
<tr class="header">
<th>Alternative Flow</th>
<th>None.</th>
</tr>
<tr class="odd">
<th>Exception Flow</th>
<th>None.</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

<table>
<colgroup>
<col style="width: 25%" />
<col style="width: 75%" />
</colgroup>
<thead>
<tr class="header">
<th>Use Case Name</th>
<th>UC2.6 Ask AI Health Agent</th>
</tr>
<tr class="odd">
<th>Brief Description</th>
<th>Patient-initiated query to the conversational AI Health Agent (Google Gemini Flash), grounded in the patient's live vitals, risk scores, and medications.</th>
</tr>
<tr class="header">
<th>Characteristic of activation</th>
<th>Triggered when the Patient sends a message to the AI agent.</th>
</tr>
<tr class="odd">
<th>Primary Actor</th>
<th>Patient</th>
</tr>
<tr class="header">
<th>Secondary Actor</th>
<th>System</th>
</tr>
<tr class="odd">
<th>Pre-Condition(s)</th>
<th>The patient is authenticated.</th>
</tr>
<tr class="header">
<th colspan="2">Flow of Event</th>
</tr>
<tr class="odd">
<th>Basic Flow</th>
<th><p>1. Patient types a question.</p>
<p>2. The system assembles context (vitals, risk scores, medications, medical history).</p>
<p>3. The system sends the query and context to the Gemini API.</p>
<p>4. The system returns a plain-language response to the patient.</p></th>
</tr>
<tr class="header">
<th>Alternative Flow</th>
<th>A1: Patient asks about a risk score, specifically the system explains the score and contributing factors.</th>
</tr>
<tr class="odd">
<th>Exception Flow</th>
<th>E1: AI API call fails or times out system displays a fallback message and suggests contacting the care team directly.</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

<table>
<colgroup>
<col style="width: 25%" />
<col style="width: 75%" />
</colgroup>
<thead>
<tr class="header">
<th>Use Case Name</th>
<th>UC2.7 Receive Proactive Health Update</th>
</tr>
<tr class="odd">
<th>Brief Description</th>
<th>System-generated status message delivered automatically after each vital entry, summarising the updated risk level and next-step guidance.</th>
</tr>
<tr class="header">
<th>Characteristic of activation</th>
<th>Triggered automatically immediately after Log Blood Pressure Reading (UC3.1) completes and a new risk score is generated.</th>
</tr>
<tr class="odd">
<th>Primary Actor</th>
<th>System</th>
</tr>
<tr class="header">
<th>Secondary Actor</th>
<th>Patient</th>
</tr>
<tr class="odd">
<th>Pre-Condition(s)</th>
<th>A new vital reading has just been logged and a risk score generated.</th>
</tr>
<tr class="header">
<th colspan="2">Flow of Event</th>
</tr>
<tr class="odd">
<th>Basic Flow</th>
<th><p>1. The system detects a new risk score following a vital entry.</p>
<p>2. The system composes a plain-language status update via the AI Health Agent.</p>
<p>3. The system displays the update to the patient with relevant action buttons (e.g. Book Appointment for High risk, Alert Family for Critical).</p></th>
</tr>
<tr class="header">
<th>Alternative Flow</th>
<th>None.</th>
</tr>
<tr class="odd">
<th>Exception Flow</th>
<th>None.</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

**3.4.3 Module 3 Vital Signs Tracking**


*Figure 3.28: Use Case Diagram – Module 3: Vital Signs Tracking*

<table>
<colgroup>
<col style="width: 25%" />
<col style="width: 75%" />
</colgroup>
<thead>
<tr class="header">
<th>Use Case Name</th>
<th>UC3.1 Log Blood Pressure Reading</th>
</tr>
<tr class="odd">
<th>Brief Description</th>
<th>Manual entry of a blood pressure reading, the platform's primary continuous-monitoring input.</th>
</tr>
<tr class="header">
<th>Characteristic of activation</th>
<th>Triggered when the Patient opens Vital Signs Tracking and submits a reading.</th>
</tr>
<tr class="odd">
<th>Primary Actor</th>
<th>Patient</th>
</tr>
<tr class="header">
<th>Secondary Actor</th>
<th>System</th>
</tr>
<tr class="odd">
<th>Pre-Condition(s)</th>
<th>The patient is authenticated.</th>
</tr>
<tr class="header">
<th colspan="2">Flow of Event</th>
</tr>
<tr class="odd">
<th>Basic Flow</th>
<th><p>1. The patient opens the Vital Signs Tracking screen.</p>
<p>2. The patient enters systolic and diastolic values.</p>
<p>3. The system validates the reading is within a plausible physiological range.</p>
<p>4. The system saves the reading, timestamped, to Firestore.</p>
<p>5. System triggers Generate Risk Score (UC9.1).</p></th>
</tr>
<tr class="header">
<th>Alternative Flow</th>
<th>A1: Patient adds an optional note (UC3.2) before saving.</th>
</tr>
<tr class="odd">
<th>Exception Flow</th>
<th>E1: Reading outside the plausible range (e.g. systolic 400) system rejects the entry and asks the patient to re-check.</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

<table>
<colgroup>
<col style="width: 25%" />
<col style="width: 75%" />
</colgroup>
<thead>
<tr class="header">
<th>Use Case Name</th>
<th>UC3.2 Add Note to Reading</th>
</tr>
<tr class="odd">
<th>Brief Description</th>
<th>Optional free-text annotation on a BP entry (e.g. "after exercise"). Extends Log Blood Pressure Reading (UC3.1) as an optional, same-session step.</th>
</tr>
<tr class="header">
<th>Characteristic of activation</th>
<th>Triggered when the Patient chooses to add a note during logging.</th>
</tr>
<tr class="odd">
<th>Primary Actor</th>
<th>Patient</th>
</tr>
<tr class="header">
<th>Secondary Actor</th>
<th>None</th>
</tr>
<tr class="odd">
<th>Pre-Condition(s)</th>
<th>The patient is in the process of logging a reading (UC3.1).</th>
</tr>
<tr class="header">
<th colspan="2">Flow of Event</th>
</tr>
<tr class="odd">
<th>Basic Flow</th>
<th><p>1. Patient types a note.</p>
<p>2. The system attaches it to the reading being saved.</p></th>
</tr>
<tr class="header">
<th>Alternative Flow</th>
<th>None.</th>
</tr>
<tr class="odd">
<th>Exception Flow</th>
<th>None.</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

<table>
<colgroup>
<col style="width: 25%" />
<col style="width: 75%" />
</colgroup>
<thead>
<tr class="header">
<th>Use Case Name</th>
<th>UC3.3 Capture Heart Rate (PPG)</th>
</tr>
<tr class="odd">
<th>Brief Description</th>
<th>Captures heart rate using the smartphone camera: the patient's fingertip over the lens, analysed via green-channel pixel intensity and peak detection (Yan et al., 2017).</th>
</tr>
<tr class="header">
<th>Characteristic of activation</th>
<th>Triggered when the Patient places a finger over the camera during a vitals or symptom-checker session.</th>
</tr>
<tr class="odd">
<th>Primary Actor</th>
<th>Patient</th>
</tr>
<tr class="header">
<th>Secondary Actor</th>
<th>System</th>
</tr>
<tr class="odd">
<th>Pre-Condition(s)</th>
<th>The device has a functioning rear camera; sufficient ambient lighting.</th>
</tr>
<tr class="header">
<th colspan="2">Flow of Event</th>
</tr>
<tr class="odd">
<th>Basic Flow</th>
<th><p>1. The patient places fingertip over the camera lens.</p>
<p>2. The system captures RGB frames and isolates the green channel.</p>
<p>3. The system applies peak detection to compute beats per minute.</p>
<p>4. The system stores the value alongside the current session (vitals entry or symptom checker).</p></th>
</tr>
<tr class="header">
<th>Alternative Flow</th>
<th>None.</th>
</tr>
<tr class="odd">
<th>Exception Flow</th>
<th>E1: Poor signal (movement, lighting, placement) system prompts the patient to reposition and retry.</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

**3.4.4 Module 4 Health Data Visualisation**


*Figure 3.29: Use Case Diagram – Module 4: Health Data Visualisation*

<table>
<colgroup>
<col style="width: 25%" />
<col style="width: 75%" />
</colgroup>
<thead>
<tr class="header">
<th>Use Case Name</th>
<th>UC4.1 View BP Trend Chart</th>
</tr>
<tr class="odd">
<th>Brief Description</th>
<th>Displays interactive blood pressure trend charts across 7-day, 30-day, 3-month, and 1-year views.</th>
</tr>
<tr class="header">
<th>Characteristic of activation</th>
<th>Triggered when the actor opens the visualisation screen (patient for their own data; doctor for an assigned patient's data).</th>
</tr>
<tr class="odd">
<th>Primary Actor</th>
<th>Patient, Doctor</th>
</tr>
<tr class="header">
<th>Secondary Actor</th>
<th>None</th>
</tr>
<tr class="odd">
<th>Pre-Condition(s)</th>
<th>At least one BP reading exists for the patient in question.</th>
</tr>
<tr class="header">
<th colspan="2">Flow of Event</th>
</tr>
<tr class="odd">
<th>Basic Flow</th>
<th><p>1. Actor selects a timeframe.</p>
<p>2. System retrieves readings within that range.</p>
<p>3. The system renders the trend chart.</p></th>
</tr>
<tr class="header">
<th>Alternative Flow</th>
<th>A1: Actor switches timeframe system re-renders without leaving the screen.</th>
</tr>
<tr class="odd">
<th>Exception Flow</th>
<th>E1: No readings in the selected range system displays an empty chart with a message.</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

<table>
<colgroup>
<col style="width: 25%" />
<col style="width: 75%" />
</colgroup>
<thead>
<tr class="header">
<th>Use Case Name</th>
<th>UC4.2 View Statistical Summary</th>
</tr>
<tr class="odd">
<th>Brief Description</th>
<th>Displays average, minimum, and maximum BP values for the selected period.</th>
</tr>
<tr class="header">
<th>Characteristic of activation</th>
<th>Rendered alongside the trend chart.</th>
</tr>
<tr class="odd">
<th>Primary Actor</th>
<th>Patient, Doctor</th>
</tr>
<tr class="header">
<th>Secondary Actor</th>
<th>None</th>
</tr>
<tr class="odd">
<th>Pre-Condition(s)</th>
<th>At least one BP reading exists in the selected range.</th>
</tr>
<tr class="header">
<th colspan="2">Flow of Event</th>
</tr>
<tr class="odd">
<th>Basic Flow</th>
<th><p>1. The system computes average/min/max over the selected range.</p>
<p>2. The system displays the summary alongside the chart.</p></th>
</tr>
<tr class="header">
<th>Alternative Flow</th>
<th>None.</th>
</tr>
<tr class="odd">
<th>Exception Flow</th>
<th>E1: Insufficient data (fewer than two readings) system displays available values and omits trend-based statistics.</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

<table>
<colgroup>
<col style="width: 25%" />
<col style="width: 75%" />
</colgroup>
<thead>
<tr class="header">
<th>Use Case Name</th>
<th>UC4.3 Compare Multiple Vitals</th>
</tr>
<tr class="odd">
<th>Brief Description</th>
<th>Overlays BP against another vital (e.g. heart rate) on a single chart.</th>
</tr>
<tr class="header">
<th>Characteristic of activation</th>
<th>Triggered when the actor selects a second vital to overlay.</th>
</tr>
<tr class="odd">
<th>Primary Actor</th>
<th>Patient, Doctor</th>
</tr>
<tr class="header">
<th>Secondary Actor</th>
<th>None</th>
</tr>
<tr class="odd">
<th>Pre-Condition(s)</th>
<th>Readings exist for both selected vitals.</th>
</tr>
<tr class="header">
<th colspan="2">Flow of Event</th>
</tr>
<tr class="odd">
<th>Basic Flow</th>
<th><p>1. The actor selects a second vital.</p>
<p>2. The system retrieves and overlays both series on one chart.</p></th>
</tr>
<tr class="header">
<th>Alternative Flow</th>
<th>None.</th>
</tr>
<tr class="odd">
<th>Exception Flow</th>
<th>E1: Second vital has no data in range system displays the primary vital only and notes the gap.</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

<table>
<colgroup>
<col style="width: 25%" />
<col style="width: 75%" />
</colgroup>
<thead>
<tr class="header">
<th>Use Case Name</th>
<th>UC4.4 View Risk Score Trend</th>
</tr>
<tr class="odd">
<th>Brief Description</th>
<th>Displays the historical trend of ML-predicted disease risk scores over time.</th>
</tr>
<tr class="header">
<th>Characteristic of activation</th>
<th>Triggered when the actor opens the risk trend view.</th>
</tr>
<tr class="odd">
<th>Primary Actor</th>
<th>Patient, Doctor</th>
</tr>
<tr class="header">
<th>Secondary Actor</th>
<th>System</th>
</tr>
<tr class="odd">
<th>Pre-Condition(s)</th>
<th>At least two risk scores have been generated over time.</th>
</tr>
<tr class="header">
<th colspan="2">Flow of Event</th>
</tr>
<tr class="odd">
<th>Basic Flow</th>
<th><p>1. The system retrieves historical risk scores.</p>
<p>2. The system renders the trend per complication.</p></th>
</tr>
<tr class="header">
<th>Alternative Flow</th>
<th>None.</th>
</tr>
<tr class="odd">
<th>Exception Flow</th>
<th>E1: Fewer than two data points system displays the single available score without a trend line.</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

**3.4.5 Module 5 Medication Management**


*Figure 3.30: Use Case Diagram – Module 5: Medication Management*

<table>
<colgroup>
<col style="width: 25%" />
<col style="width: 75%" />
</colgroup>
<thead>
<tr class="header">
<th>Use Case Name</th>
<th>UC5.1 Manage Personal Medication List</th>
</tr>
<tr class="odd">
<th>Brief Description</th>
<th>Add, edit, or delete entries in the patient's own medication tracking and reminder list. Governs reminder scheduling and self-tracking only, not the doctor's clinical prescription record.</th>
</tr>
<tr class="header">
<th>Characteristic of activation</th>
<th>Triggered when the Patient opens the medication list and adds/edits/deletes an entry.</th>
</tr>
<tr class="odd">
<th>Primary Actor</th>
<th>Patient</th>
</tr>
<tr class="header">
<th>Secondary Actor</th>
<th>None</th>
</tr>
<tr class="odd">
<th>Pre-Condition(s)</th>
<th>The patient is authenticated.</th>
</tr>
<tr class="header">
<th colspan="2">Flow of Event</th>
</tr>
<tr class="odd">
<th>Basic Flow</th>
<th><p>1. The patient opens the medication list.</p>
<p>2. Patient adds, edits, or deletes an entry (name, dosage, schedule).</p>
<p>3. The system validates and saves the change.</p></th>
</tr>
<tr class="header">
<th>Alternative Flow</th>
<th>None.</th>
</tr>
<tr class="odd">
<th>Exception Flow</th>
<th>E1: Duplicate or conflicting schedule entry system warns the patient before saving.</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

<table>
<colgroup>
<col style="width: 25%" />
<col style="width: 75%" />
</colgroup>
<thead>
<tr class="header">
<th>Use Case Name</th>
<th>UC5.2 Receive Refill Alert</th>
</tr>
<tr class="odd">
<th>Brief Description</th>
<th>Automated alert when remaining medication supply drops below a threshold. Extends Manage Personal Medication List (UC5.1); System-triggered.</th>
</tr>
<tr class="header">
<th>Characteristic of activation</th>
<th>Triggered automatically when computed remaining supply falls below the configured threshold.</th>
</tr>
<tr class="odd">
<th>Primary Actor</th>
<th>System</th>
</tr>
<tr class="header">
<th>Secondary Actor</th>
<th>Patient</th>
</tr>
<tr class="odd">
<th>Pre-Condition(s)</th>
<th>A medication's dosage/schedule data exists and consumption has been tracked.</th>
</tr>
<tr class="header">
<th colspan="2">Flow of Event</th>
</tr>
<tr class="odd">
<th>Basic Flow</th>
<th><p>1. The system computes remaining supply from schedule and adherence data.</p>
<p>2. System detects supply below threshold.</p>
<p>3. The system sends a refill alert to the patient.</p></th>
</tr>
<tr class="header">
<th>Alternative Flow</th>
<th>None.</th>
</tr>
<tr class="odd">
<th>Exception Flow</th>
<th>None.</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

<table>
<colgroup>
<col style="width: 25%" />
<col style="width: 75%" />
</colgroup>
<thead>
<tr class="header">
<th>Use Case Name</th>
<th>UC5.3 Receive Reminder</th>
</tr>
<tr class="odd">
<th>Brief Description</th>
<th>Scheduled push notification prompting the patient to take a dose.</th>
</tr>
<tr class="header">
<th>Characteristic of activation</th>
<th>Triggered at the scheduled dose time.</th>
</tr>
<tr class="odd">
<th>Primary Actor</th>
<th>Patient</th>
</tr>
<tr class="header">
<th>Secondary Actor</th>
<th>System</th>
</tr>
<tr class="odd">
<th>Pre-Condition(s)</th>
<th>A medication schedule exists (UC5.1).</th>
</tr>
<tr class="header">
<th colspan="2">Flow of Event</th>
</tr>
<tr class="odd">
<th>Basic Flow</th>
<th><p>1. The system reaches the scheduled dose time.</p>
<p>2. The system sends a push notification.</p>
<p>3. The patient confirms the dose was taken.</p></th>
</tr>
<tr class="header">
<th>Alternative Flow</th>
<th>None.</th>
</tr>
<tr class="odd">
<th>Exception Flow</th>
<th>E1: Patient does not respond within the window system triggers Log Missed Dose (UC5.4).</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

<table>
<colgroup>
<col style="width: 25%" />
<col style="width: 75%" />
</colgroup>
<thead>
<tr class="header">
<th>Use Case Name</th>
<th>UC5.4 Log Missed Dose</th>
</tr>
<tr class="odd">
<th>Brief Description</th>
<th>Automatically records a dose as missed when not confirmed within the reminder window. Extends Receive Reminder (UC5.3); System-triggered.</th>
</tr>
<tr class="header">
<th>Characteristic of activation</th>
<th>Triggered automatically when the confirmation window following a reminder elapses without patient action.</th>
</tr>
<tr class="odd">
<th>Primary Actor</th>
<th>System</th>
</tr>
<tr class="header">
<th>Secondary Actor</th>
<th>Patient</th>
</tr>
<tr class="odd">
<th>Pre-Condition(s)</th>
<th>A reminder (UC5.3) has been sent and the response window has elapsed.</th>
</tr>
<tr class="header">
<th colspan="2">Flow of Event</th>
</tr>
<tr class="odd">
<th>Basic Flow</th>
<th><p>1. The system detects the window has elapsed with no confirmation.</p>
<p>2. The system logs the dose as missed.</p>
<p>3. System updates the adherence rate (UC5.5).</p></th>
</tr>
<tr class="header">
<th>Alternative Flow</th>
<th>None.</th>
</tr>
<tr class="odd">
<th>Exception Flow</th>
<th>None.</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

<table>
<colgroup>
<col style="width: 25%" />
<col style="width: 75%" />
</colgroup>
<thead>
<tr class="header">
<th>Use Case Name</th>
<th>UC5.5 View Adherence Rate</th>
</tr>
<tr class="odd">
<th>Brief Description</th>
<th>Displays the calculated percentage of doses taken on schedule.</th>
</tr>
<tr class="header">
<th>Characteristic of activation</th>
<th>Triggered when the Patient opens the adherence view.</th>
</tr>
<tr class="odd">
<th>Primary Actor</th>
<th>Patient</th>
</tr>
<tr class="header">
<th>Secondary Actor</th>
<th>System</th>
</tr>
<tr class="odd">
<th>Pre-Condition(s)</th>
<th>At least one reminder cycle has occurred.</th>
</tr>
<tr class="header">
<th colspan="2">Flow of Event</th>
</tr>
<tr class="odd">
<th>Basic Flow</th>
<th><p>1. System computes adherence rate from confirmed vs. missed doses.</p>
<p>2. The system displays the rate to the patient.</p></th>
</tr>
<tr class="header">
<th>Alternative Flow</th>
<th>None.</th>
</tr>
<tr class="odd">
<th>Exception Flow</th>
<th>E1: No dose history yet system displays an empty state.</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

<table>
<colgroup>
<col style="width: 25%" />
<col style="width: 75%" />
</colgroup>
<thead>
<tr class="header">
<th>Use Case Name</th>
<th>UC5.6 Receive Drug Interaction Alert</th>
</tr>
<tr class="odd">
<th>Brief Description</th>
<th>Automated warning when a newly added medication conflicts with an existing entry on the patient's medication list. Extends Manage Personal Medication List (UC5.1); System-triggered.</th>
</tr>
<tr class="header">
<th>Characteristic of activation</th>
<th>Triggered automatically when a newly added or edited medication is detected to interact with an existing entry.</th>
</tr>
<tr class="odd">
<th>Primary Actor</th>
<th>System</th>
</tr>
<tr class="header">
<th>Secondary Actor</th>
<th>Patient</th>
</tr>
<tr class="odd">
<th>Pre-Condition(s)</th>
<th>At least one existing medication entry exists (UC5.1).</th>
</tr>
<tr class="header">
<th colspan="2">Flow of Event</th>
</tr>
<tr class="odd">
<th>Basic Flow</th>
<th><p>1. Patient adds or edits a medication entry.</p>
<p>2. The system cross-checks the new entry against the existing medication list for known interactions.</p>
<p>3. The system detects a conflicting interaction.</p>
<p>4. The system displays a drug interaction warning to the patient.</p></th>
</tr>
<tr class="header">
<th>Alternative Flow</th>
<th>None.</th>
</tr>
<tr class="odd">
<th>Exception Flow</th>
<th>E1: Interaction severity is critical system blocks saving the entry until the patient acknowledges or removes the conflicting item.</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

**3.4.6 Module 6 Health Records Management**


*Figure 3.31: Use Case Diagram – Module 6: Health Records Management*

<table>
<colgroup>
<col style="width: 25%" />
<col style="width: 75%" />
</colgroup>
<thead>
<tr class="header">
<th>Use Case Name</th>
<th>UC6.1 Upload &amp; Categorise Document</th>
</tr>
<tr class="odd">
<th>Brief Description</th>
<th>Upload a medical document and assign it a category; categorisation is a mandatory same-session step.</th>
</tr>
<tr class="header">
<th>Characteristic of activation</th>
<th>Triggered when the Patient uploads a file.</th>
</tr>
<tr class="odd">
<th>Primary Actor</th>
<th>Patient</th>
</tr>
<tr class="header">
<th>Secondary Actor</th>
<th>None</th>
</tr>
<tr class="odd">
<th>Pre-Condition(s)</th>
<th>The patient is authenticated.</th>
</tr>
<tr class="header">
<th colspan="2">Flow of Event</th>
</tr>
<tr class="odd">
<th>Basic Flow</th>
<th><p>1. The patient selects a file to upload.</p>
<p>2. The system uploads it to Firebase Storage.</p>
<p>3. The patient assigns a category.</p>
<p>4. The system saves the categorised record.</p></th>
</tr>
<tr class="header">
<th>Alternative Flow</th>
<th>None.</th>
</tr>
<tr class="odd">
<th>Exception Flow</th>
<th><p>E1: Unsupported file type system rejects the upload and lists supported formats.</p>
<p>E2: Upload fails (network) system retries and notifies the patient on repeated failure.</p></th>
</tr>
</thead>
<tbody>
</tbody>
</table>

<table>
<colgroup>
<col style="width: 25%" />
<col style="width: 75%" />
</colgroup>
<thead>
<tr class="header">
<th>Use Case Name</th>
<th>UC6.2 Share Document with Doctor</th>
</tr>
<tr class="odd">
<th>Brief Description</th>
<th>Voluntary, later decision to share a previously uploaded document with the assigned doctor. Extends Upload &amp; Categorise Document (UC6.1).</th>
</tr>
<tr class="header">
<th>Characteristic of activation</th>
<th>Triggered when the Patient chooses to share an existing document.</th>
</tr>
<tr class="odd">
<th>Primary Actor</th>
<th>Patient</th>
</tr>
<tr class="header">
<th>Secondary Actor</th>
<th>Doctor</th>
</tr>
<tr class="odd">
<th>Pre-Condition(s)</th>
<th>At least one document has been uploaded (UC6.1).</th>
</tr>
<tr class="header">
<th colspan="2">Flow of Event</th>
</tr>
<tr class="odd">
<th>Basic Flow</th>
<th><p>1. The patient selects a document.</p>
<p>2. The patient chooses to share with the Doctor.</p>
<p>3. The system grants the assigned doctor access to the document.</p></th>
</tr>
<tr class="header">
<th>Alternative Flow</th>
<th>None.</th>
</tr>
<tr class="odd">
<th>Exception Flow</th>
<th>None.</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

<table>
<colgroup>
<col style="width: 25%" />
<col style="width: 75%" />
</colgroup>
<thead>
<tr class="header">
<th>Use Case Name</th>
<th>UC6.3 View Shared Records</th>
</tr>
<tr class="odd">
<th>Brief Description</th>
<th>Allows the doctor to view documents a patient has shared.</th>
</tr>
<tr class="header">
<th>Characteristic of activation</th>
<th>Triggered when the Doctor opens a patient's shared records.</th>
</tr>
<tr class="odd">
<th>Primary Actor</th>
<th>Doctor</th>
</tr>
<tr class="header">
<th>Secondary Actor</th>
<th>None</th>
</tr>
<tr class="odd">
<th>Pre-Condition(s)</th>
<th>At least one document has been shared (UC6.2).</th>
</tr>
<tr class="header">
<th colspan="2">Flow of Event</th>
</tr>
<tr class="odd">
<th>Basic Flow</th>
<th><p>1. The doctor opens the patient's record.</p>
<p>2. The system displays shared documents.</p></th>
</tr>
<tr class="header">
<th>Alternative Flow</th>
<th>None.</th>
</tr>
<tr class="odd">
<th>Exception Flow</th>
<th>E1: No documents shared system displays an empty state.</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

**3.4.7 Module 7 Appointment Scheduling**


*Figure 3.32: Use Case Diagram – Module 7: Appointment Scheduling*

<table>
<colgroup>
<col style="width: 25%" />
<col style="width: 75%" />
</colgroup>
<thead>
<tr class="header">
<th>Use Case Name</th>
<th>UC7.1 Book Appointment</th>
</tr>
<tr class="odd">
<th>Brief Description</th>
<th>Schedules a new consultation between a patient and a doctor.</th>
</tr>
<tr class="header">
<th>Characteristic of activation</th>
<th>Triggered when the Patient submits a booking request.</th>
</tr>
<tr class="odd">
<th>Primary Actor</th>
<th>Patient</th>
</tr>
<tr class="header">
<th>Secondary Actor</th>
<th>Admin</th>
</tr>
<tr class="odd">
<th>Pre-Condition(s)</th>
<th>The patient is authenticated.</th>
</tr>
<tr class="header">
<th colspan="2">Flow of Event</th>
</tr>
<tr class="odd">
<th>Basic Flow</th>
<th><p>1. The patient selects a preferred date/time.</p>
<p>2. The system checks doctor availability.</p>
<p>3. System triggers Assign Doctor to Patient (UC7.3) if none is yet assigned.</p>
<p>4. The system confirms the booking and triggers Receive Appointment Reminder (UC7.4) and View Pre-Visit Summary (UC7.5).</p></th>
</tr>
<tr class="header">
<th>Alternative Flow</th>
<th>A1: Disease risk is High/Critical system proactively prompts the patient to book (per Module 9).</th>
</tr>
<tr class="odd">
<th>Exception Flow</th>
<th>E1: No slots available in the desired window system offers the nearest alternatives.</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

<table>
<colgroup>
<col style="width: 25%" />
<col style="width: 75%" />
</colgroup>
<thead>
<tr class="header">
<th>Use Case Name</th>
<th>UC7.2 Reschedule or Cancel Appointment</th>
</tr>
<tr class="odd">
<th>Brief Description</th>
<th>Patient-initiated, later modification of an existing booking. Extends Book Appointment (UC7.1).</th>
</tr>
<tr class="header">
<th>Characteristic of activation</th>
<th>Triggered when the Patient selects Reschedule or Cancel on an existing booking.</th>
</tr>
<tr class="odd">
<th>Primary Actor</th>
<th>Patient</th>
</tr>
<tr class="header">
<th>Secondary Actor</th>
<th>Doctor</th>
</tr>
<tr class="odd">
<th>Pre-Condition(s)</th>
<th>A booked appointment (UC7.1) exists.</th>
</tr>
<tr class="header">
<th colspan="2">Flow of Event</th>
</tr>
<tr class="odd">
<th>Basic Flow</th>
<th><p>1. The patient selects an existing appointment.</p>
<p>2. The patient chooses Reschedule (selects a new slot) or Cancel.</p>
<p>3. The system updates the booking and notifies the doctor.</p></th>
</tr>
<tr class="header">
<th>Alternative Flow</th>
<th>None.</th>
</tr>
<tr class="odd">
<th>Exception Flow</th>
<th>E1: Cancellation attempted within a restricted window system warns the patient before confirming.</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

<table>
<colgroup>
<col style="width: 25%" />
<col style="width: 75%" />
</colgroup>
<thead>
<tr class="header">
<th>Use Case Name</th>
<th>UC7.3 Assign Doctor to Patient</th>
</tr>
<tr class="odd">
<th>Brief Description</th>
<th>Admin assigns the attending doctor for a booking.</th>
</tr>
<tr class="header">
<th>Characteristic of activation</th>
<th>Triggered when a booking requires a doctor assignment.</th>
</tr>
<tr class="odd">
<th>Primary Actor</th>
<th>Admin</th>
</tr>
<tr class="header">
<th>Secondary Actor</th>
<th>Patient</th>
</tr>
<tr class="odd">
<th>Pre-Condition(s)</th>
<th>A booking request exists without an assigned doctor.</th>
</tr>
<tr class="header">
<th colspan="2">Flow of Event</th>
</tr>
<tr class="odd">
<th>Basic Flow</th>
<th><p>1. Admin reviews the booking.</p>
<p>2. Admin selects an available doctor.</p>
<p>3. The system links the doctor to the booking and the patient's care team.</p></th>
</tr>
<tr class="header">
<th>Alternative Flow</th>
<th>None.</th>
</tr>
<tr class="odd">
<th>Exception Flow</th>
<th>E1: No doctor available for the requested specialty/time system flags the booking for manual follow-up.</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

<table>
<colgroup>
<col style="width: 25%" />
<col style="width: 75%" />
</colgroup>
<thead>
<tr class="header">
<th>Use Case Name</th>
<th>UC7.4 Receive Appointment Reminder</th>
</tr>
<tr class="odd">
<th>Brief Description</th>
<th>Push/email reminder sent ahead of a scheduled appointment.</th>
</tr>
<tr class="header">
<th>Characteristic of activation</th>
<th>Triggered at a configured interval before the appointment time.</th>
</tr>
<tr class="odd">
<th>Primary Actor</th>
<th>Patient</th>
</tr>
<tr class="header">
<th>Secondary Actor</th>
<th>System</th>
</tr>
<tr class="odd">
<th>Pre-Condition(s)</th>
<th>A booked appointment exists (UC7.1).</th>
</tr>
<tr class="header">
<th colspan="2">Flow of Event</th>
</tr>
<tr class="odd">
<th>Basic Flow</th>
<th><p>1. The system reaches the reminder interval.</p>
<p>2. The system sends a push notification and email.</p></th>
</tr>
<tr class="header">
<th>Alternative Flow</th>
<th>None.</th>
</tr>
<tr class="odd">
<th>Exception Flow</th>
<th>None.</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

<table>
<colgroup>
<col style="width: 25%" />
<col style="width: 75%" />
</colgroup>
<thead>
<tr class="header">
<th>Use Case Name</th>
<th>UC7.5 View Pre-Visit Summary</th>
</tr>
<tr class="odd">
<th>Brief Description</th>
<th>System-generated summary (recent vitals, risk scores, notes) the doctor reviews shortly before the visit.</th>
</tr>
<tr class="header">
<th>Characteristic of activation</th>
<th>Generated automatically ahead of a scheduled appointment.</th>
</tr>
<tr class="odd">
<th>Primary Actor</th>
<th>Doctor</th>
</tr>
<tr class="header">
<th>Secondary Actor</th>
<th>System</th>
</tr>
<tr class="odd">
<th>Pre-Condition(s)</th>
<th>A booked appointment exists (UC7.1).</th>
</tr>
<tr class="header">
<th colspan="2">Flow of Event</th>
</tr>
<tr class="odd">
<th>Basic Flow</th>
<th><p>1. The system compiles the patient's recent vitals, risk scores, and open items.</p>
<p>2. The doctor opens the summary before the consultation.</p></th>
</tr>
<tr class="header">
<th>Alternative Flow</th>
<th>None.</th>
</tr>
<tr class="odd">
<th>Exception Flow</th>
<th>E1: Insufficient recent data system displays available history and flags data gaps.</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

**3.4.8 Module 8 Healthcare Provider Portal**


*Figure 3.33: Use Case Diagram – Module 8: Healthcare Provider Portal*

<table>
<colgroup>
<col style="width: 25%" />
<col style="width: 75%" />
</colgroup>
<thead>
<tr class="header">
<th>Use Case Name</th>
<th>UC8.1 View Assigned Patient List</th>
</tr>
<tr class="odd">
<th>Brief Description</th>
<th>Displays the list of patients assigned to the doctor.</th>
</tr>
<tr class="header">
<th>Characteristic of activation</th>
<th>Triggered when the Doctor opens the portal.</th>
</tr>
<tr class="odd">
<th>Primary Actor</th>
<th>Doctor</th>
</tr>
<tr class="header">
<th>Secondary Actor</th>
<th>None</th>
</tr>
<tr class="odd">
<th>Pre-Condition(s)</th>
<th>At least one patient is assigned to the doctor.</th>
</tr>
<tr class="header">
<th colspan="2">Flow of Event</th>
</tr>
<tr class="odd">
<th>Basic Flow</th>
<th><p>1. The Doctor opens the portal.</p>
<p>2. The system retrieves and displays the assigned patient list.</p></th>
</tr>
<tr class="header">
<th>Alternative Flow</th>
<th>None.</th>
</tr>
<tr class="odd">
<th>Exception Flow</th>
<th>E1: No patients assigned to the system display an empty state.</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

<table>
<colgroup>
<col style="width: 25%" />
<col style="width: 75%" />
</colgroup>
<thead>
<tr class="header">
<th>Use Case Name</th>
<th>UC8.2 Filter Patients by Risk Level</th>
</tr>
<tr class="odd">
<th>Brief Description</th>
<th>Optional refinement of the patient list by ML-predicted risk category. Extends View Assigned Patient List (UC8.1).</th>
</tr>
<tr class="header">
<th>Characteristic of activation</th>
<th>Triggered when the Doctor applies a risk-level filter.</th>
</tr>
<tr class="odd">
<th>Primary Actor</th>
<th>Doctor</th>
</tr>
<tr class="header">
<th>Secondary Actor</th>
<th>None</th>
</tr>
<tr class="odd">
<th>Pre-Condition(s)</th>
<th>The assigned patient list (UC8.1) is displayed.</th>
</tr>
<tr class="header">
<th colspan="2">Flow of Event</th>
</tr>
<tr class="odd">
<th>Basic Flow</th>
<th><p>1. The doctor selects one or more risk levels.</p>
<p>2. The system filters the displayed list accordingly.</p></th>
</tr>
<tr class="header">
<th>Alternative Flow</th>
<th>A1: Doctor clears the filter system restores the full list.</th>
</tr>
<tr class="odd">
<th>Exception Flow</th>
<th>None.</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

<table>
<colgroup>
<col style="width: 25%" />
<col style="width: 75%" />
</colgroup>
<thead>
<tr class="header">
<th>Use Case Name</th>
<th>UC8.3 View Patient Health History</th>
</tr>
<tr class="odd">
<th>Brief Description</th>
<th>Displays full vitals, medication, and records history for one assigned patient.</th>
</tr>
<tr class="header">
<th>Characteristic of activation</th>
<th>Triggered when the Doctor selects a patient from the list.</th>
</tr>
<tr class="odd">
<th>Primary Actor</th>
<th>Doctor</th>
</tr>
<tr class="header">
<th>Secondary Actor</th>
<th>None</th>
</tr>
<tr class="odd">
<th>Pre-Condition(s)</th>
<th>The patient is assigned to the doctor (UC7.3).</th>
</tr>
<tr class="header">
<th colspan="2">Flow of Event</th>
</tr>
<tr class="odd">
<th>Basic Flow</th>
<th><p>1. The doctor selects a patient.</p>
<p>2. The system retrieves and displays vitals, medications, and shared records.</p></th>
</tr>
<tr class="header">
<th>Alternative Flow</th>
<th>None.</th>
</tr>
<tr class="odd">
<th>Exception Flow</th>
<th>E1: Patient has no recorded history yet system displays an empty state.</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

<table>
<colgroup>
<col style="width: 25%" />
<col style="width: 75%" />
</colgroup>
<thead>
<tr class="header">
<th>Use Case Name</th>
<th>UC8.4 Write Clinical Note / Issue Prescription</th>
</tr>
<tr class="odd">
<th>Brief Description</th>
<th>Deliberate doctor action taken after reviewing a patient's history. Extends View Patient Health History (UC8.3).</th>
</tr>
<tr class="header">
<th>Characteristic of activation</th>
<th>Triggered when the Doctor chooses to add a note or issue a prescription.</th>
</tr>
<tr class="odd">
<th>Primary Actor</th>
<th>Doctor</th>
</tr>
<tr class="header">
<th>Secondary Actor</th>
<th>Pharmacist</th>
</tr>
<tr class="odd">
<th>Pre-Condition(s)</th>
<th>The doctor is viewing the patient's health history (UC8.3).</th>
</tr>
<tr class="header">
<th colspan="2">Flow of Event</th>
</tr>
<tr class="odd">
<th>Basic Flow</th>
<th><p>1. Doctor selects Add Note or Issue Prescription.</p>
<p>2. The doctor enters the note text or prescription details.</p>
<p>3. The system saves the entry to the patient's record.</p>
<p>4. If a prescription was issued, the system notifies the pharmacy.</p></th>
</tr>
<tr class="header">
<th>Alternative Flow</th>
<th>None.</th>
</tr>
<tr class="odd">
<th>Exception Flow</th>
<th>E1: Drug interaction detected against the patient's current medication list system warns before saving.</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

<table>
<colgroup>
<col style="width: 25%" />
<col style="width: 75%" />
</colgroup>
<thead>
<tr class="header">
<th>Use Case Name</th>
<th>UC8.5 Update Care Plan</th>
</tr>
<tr class="odd">
<th>Brief Description</th>
<th>Edits the shared care plan visible to the full care team for a patient.</th>
</tr>
<tr class="header">
<th>Characteristic of activation</th>
<th>Triggered when the Doctor edits the care plan.</th>
</tr>
<tr class="odd">
<th>Primary Actor</th>
<th>Doctor</th>
</tr>
<tr class="header">
<th>Secondary Actor</th>
<th>Patient</th>
</tr>
<tr class="odd">
<th>Pre-Condition(s)</th>
<th>The patient is assigned to the doctor.</th>
</tr>
<tr class="header">
<th colspan="2">Flow of Event</th>
</tr>
<tr class="odd">
<th>Basic Flow</th>
<th><p>1. The doctor opens the care plan.</p>
<p>2. Doctor edits it.</p>
<p>3. The system saves and syncs the update to the patient's shared view (UC10.2).</p></th>
</tr>
<tr class="header">
<th>Alternative Flow</th>
<th>None.</th>
</tr>
<tr class="odd">
<th>Exception Flow</th>
<th>None.</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

<table>
<colgroup>
<col style="width: 25%" />
<col style="width: 75%" />
</colgroup>
<thead>
<tr class="header">
<th>Use Case Name</th>
<th>UC8.6 Receive Risk Alerts</th>
</tr>
<tr class="odd">
<th>Brief Description</th>
<th>Notifies the doctor of ML-flagged risk changes for assigned patients.</th>
</tr>
<tr class="header">
<th>Characteristic of activation</th>
<th>Triggered automatically by Module 9's escalation logic.</th>
</tr>
<tr class="odd">
<th>Primary Actor</th>
<th>Doctor</th>
</tr>
<tr class="header">
<th>Secondary Actor</th>
<th>System</th>
</tr>
<tr class="odd">
<th>Pre-Condition(s)</th>
<th>An assigned patient's risk score has escalated (Module 9).</th>
</tr>
<tr class="header">
<th colspan="2">Flow of Event</th>
</tr>
<tr class="odd">
<th>Basic Flow</th>
<th><p>1. The system detects a risk escalation for an assigned patient.</p>
<p>2. The system notifies the doctor via the portal.</p></th>
</tr>
<tr class="header">
<th>Alternative Flow</th>
<th>None.</th>
</tr>
<tr class="odd">
<th>Exception Flow</th>
<th>None.</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

**3.4.9 Module 9 AI-Powered Health Monitoring**


*Figure 3.34: Use Case Diagram – Module 9: AI-Powered Health Monitoring*

<table>
<colgroup>
<col style="width: 25%" />
<col style="width: 75%" />
</colgroup>
<thead>
<tr class="header">
<th>Use Case Name</th>
<th>UC9.1 Generate Risk Score</th>
</tr>
<tr class="odd">
<th>Brief Description</th>
<th>ML inference (Random Forest/XGBoost) predicting patient risk across five complications (stroke, coronary artery disease, heart failure, chronic kidney disease, type 2 diabetes) from twelve input variables (Breiman, 2001; Chen &amp; Guestrin, 2016).</th>
</tr>
<tr class="header">
<th>Characteristic of activation</th>
<th>Triggered automatically whenever a new vital reading or symptom-checker submission occurs.</th>
</tr>
<tr class="odd">
<th>Primary Actor</th>
<th>System</th>
</tr>
<tr class="header">
<th>Secondary Actor</th>
<th>Patient, Doctor</th>
</tr>
<tr class="odd">
<th>Pre-Condition(s)</th>
<th>Sufficient input variables (vitals, lifestyle, medical history) are available.</th>
</tr>
<tr class="header">
<th colspan="2">Flow of Event</th>
</tr>
<tr class="odd">
<th>Basic Flow</th>
<th><p>1. The system assembles the twelve input variables.</p>
<p>2. The system runs the Random Forest and XGBoost models per complication.</p>
<p>3. System selects the higher-AUC-ROC model's output per complication.</p>
<p>4. The system categorises each result as Low, Moderate, High, or Critical.</p>
<p>5. The system stores the scores and updates the Risk Score Card (UC2.4).</p></th>
</tr>
<tr class="header">
<th>Alternative Flow</th>
<th>None.</th>
</tr>
<tr class="odd">
<th>Exception Flow</th>
<th>E1: Missing input variables system uses the last known value where available and flags reduced confidence.</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

<table>
<colgroup>
<col style="width: 25%" />
<col style="width: 75%" />
</colgroup>
<thead>
<tr class="header">
<th>Use Case Name</th>
<th>UC9.2 Send Patient Alerts</th>
</tr>
<tr class="odd">
<th>Brief Description</th>
<th>Covers threshold alerts and consultation prompts. Extends Generate Risk Score (UC9.1); fires when a reading is abnormal or a risk score reaches High/Critical.</th>
</tr>
<tr class="header">
<th>Characteristic of activation</th>
<th>Triggered automatically when a reading crosses a safe threshold, or a risk score reaches High/Critical.</th>
</tr>
<tr class="odd">
<th>Primary Actor</th>
<th>System</th>
</tr>
<tr class="header">
<th>Secondary Actor</th>
<th>Patient</th>
</tr>
<tr class="odd">
<th>Pre-Condition(s)</th>
<th>A risk score or reading evaluation (UC9.1) has just been completed.</th>
</tr>
<tr class="header">
<th colspan="2">Flow of Event</th>
</tr>
<tr class="odd">
<th>Basic Flow</th>
<th><p>1. System evaluates the new reading/score against thresholds.</p>
<p>2. System categorises the alert (Mild/Moderate/Emergency threshold, or High/Critical risk).</p>
<p>3. The system delivers the alert and, where applicable, a Book Appointment prompt (UC7.1) to the patient.</p></th>
</tr>
<tr class="header">
<th>Alternative Flow</th>
<th>None.</th>
</tr>
<tr class="odd">
<th>Exception Flow</th>
<th>None.</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

<table>
<colgroup>
<col style="width: 25%" />
<col style="width: 75%" />
</colgroup>
<thead>
<tr class="header">
<th>Use Case Name</th>
<th>UC9.3 Escalate to Doctor/Family</th>
</tr>
<tr class="odd">
<th>Brief Description</th>
<th>Covers the 30-day deterioration alert, Critical-risk family emergency alert, and medication review flag. Extends Generate Risk Score (UC9.1); fires on Critical risk or a sustained worsening trend.</th>
</tr>
<tr class="header">
<th>Characteristic of activation</th>
<th>Triggered automatically when risk reaches Critical, or a 30-day worsening trend is detected.</th>
</tr>
<tr class="odd">
<th>Primary Actor</th>
<th>System</th>
</tr>
<tr class="header">
<th>Secondary Actor</th>
<th>Doctor, Family Member</th>
</tr>
<tr class="odd">
<th>Pre-Condition(s)</th>
<th>A risk score history spanning at least 30 days exists, or the current score is Critical.</th>
</tr>
<tr class="header">
<th colspan="2">Flow of Event</th>
</tr>
<tr class="odd">
<th>Basic Flow</th>
<th><p>1. System evaluates the risk trend and current level.</p>
<p>2. System notifies the assigned doctor (UC8.6) if Critical or worsening.</p>
<p>3. System triggers Send Emergency Alert to Family (UC15.2) if Critical.</p>
<p>4. System raises a medication review flag on the doctor's dashboard if risk is rising significantly.</p></th>
</tr>
<tr class="header">
<th>Alternative Flow</th>
<th>None.</th>
</tr>
<tr class="odd">
<th>Exception Flow</th>
<th>None.</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

**3.4.10 Module 10 Care Coordination and Messaging**


*Figure 3.35: Use Case Diagram – Module 10: Care Coordination and Messaging*

<table>
<colgroup>
<col style="width: 25%" />
<col style="width: 75%" />
</colgroup>
<thead>
<tr class="header">
<th>Use Case Name</th>
<th>UC10.1 Send Secure Message</th>
</tr>
<tr class="odd">
<th>Brief Description</th>
<th>End-to-end encrypted messaging between a patient and their assigned doctor.</th>
</tr>
<tr class="header">
<th>Characteristic of activation</th>
<th>Triggered when the actor sends a message.</th>
</tr>
<tr class="odd">
<th>Primary Actor</th>
<th>Patient, Doctor</th>
</tr>
<tr class="header">
<th>Secondary Actor</th>
<th>System</th>
</tr>
<tr class="odd">
<th>Pre-Condition(s)</th>
<th>A doctor is assigned to the patient.</th>
</tr>
<tr class="header">
<th colspan="2">Flow of Event</th>
</tr>
<tr class="odd">
<th>Basic Flow</th>
<th><p>1. The actor composes a message.</p>
<p>2. The system encrypts and delivers it to the recipient.</p>
<p>3. The system scans the message for high-risk keywords, triggering Escalate High-Risk Message (UC10.3) if matched.</p></th>
</tr>
<tr class="header">
<th>Alternative Flow</th>
<th>None.</th>
</tr>
<tr class="odd">
<th>Exception Flow</th>
<th>E1: Recipient not reachable (offline) message is queued and delivered on reconnect, with a push notification.</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

<table>
<colgroup>
<col style="width: 25%" />
<col style="width: 75%" />
</colgroup>
<thead>
<tr class="header">
<th>Use Case Name</th>
<th>UC10.2 View Shared Care Plan</th>
</tr>
<tr class="odd">
<th>Brief Description</th>
<th>Shared view of the current care plan across the patient-doctor relationship.</th>
</tr>
<tr class="header">
<th>Characteristic of activation</th>
<th>Triggered when the actor opens the care plan.</th>
</tr>
<tr class="odd">
<th>Primary Actor</th>
<th>Patient, Doctor</th>
</tr>
<tr class="header">
<th>Secondary Actor</th>
<th>None</th>
</tr>
<tr class="odd">
<th>Pre-Condition(s)</th>
<th>A care plan exists (UC8.5).</th>
</tr>
<tr class="header">
<th colspan="2">Flow of Event</th>
</tr>
<tr class="odd">
<th>Basic Flow</th>
<th><p>1. The actor opens the care plan.</p>
<p>2. The system displays the current, synced version.</p></th>
</tr>
<tr class="header">
<th>Alternative Flow</th>
<th>None.</th>
</tr>
<tr class="odd">
<th>Exception Flow</th>
<th>E1: No care plan created yet system displays an empty state.</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

<table>
<colgroup>
<col style="width: 25%" />
<col style="width: 75%" />
</colgroup>
<thead>
<tr class="header">
<th>Use Case Name</th>
<th>UC10.3 Escalate High-Risk Message</th>
</tr>
<tr class="odd">
<th>Brief Description</th>
<th>Automatically flags a message as urgent when a high-risk keyword (e.g. "chest pain") is detected. Extends Send Secure Message (UC10.1); System-triggered.</th>
</tr>
<tr class="header">
<th>Characteristic of activation</th>
<th>Triggered automatically during message delivery when the NLP keyword scanner finds a match.</th>
</tr>
<tr class="odd">
<th>Primary Actor</th>
<th>System</th>
</tr>
<tr class="header">
<th>Secondary Actor</th>
<th>Doctor</th>
</tr>
<tr class="odd">
<th>Pre-Condition(s)</th>
<th>A message (UC10.1) is being sent.</th>
</tr>
<tr class="header">
<th colspan="2">Flow of Event</th>
</tr>
<tr class="odd">
<th>Basic Flow</th>
<th><p>1. The system scans the outgoing message text.</p>
<p>2. The system matches one or more high-risk terms.</p>
<p>3. The system flags the message as urgent and pushes an immediate notification to the assigned doctor.</p></th>
</tr>
<tr class="header">
<th>Alternative Flow</th>
<th>None.</th>
</tr>
<tr class="odd">
<th>Exception Flow</th>
<th>E1: False positive (high-risk term used in a non-urgent context) doctor reviews and dismisses the flag; no automatic correction is applied.</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

**3.4.11 Module 11 Admin Panel**


*Figure 3.36: Use Case Diagram – Module 11: Admin Panel*

<table>
<colgroup>
<col style="width: 25%" />
<col style="width: 75%" />
</colgroup>
<thead>
<tr class="header">
<th>Use Case Name</th>
<th>UC11.1 Manage User Accounts</th>
</tr>
<tr class="odd">
<th>Brief Description</th>
<th>View, edit, or deactivate user accounts across all roles.</th>
</tr>
<tr class="header">
<th>Characteristic of activation</th>
<th>Triggered when the Admin opens account management.</th>
</tr>
<tr class="odd">
<th>Primary Actor</th>
<th>Admin</th>
</tr>
<tr class="header">
<th>Secondary Actor</th>
<th>None</th>
</tr>
<tr class="odd">
<th>Pre-Condition(s)</th>
<th>Admin is authenticated.</th>
</tr>
<tr class="header">
<th colspan="2">Flow of Event</th>
</tr>
<tr class="odd">
<th>Basic Flow</th>
<th><p>1. Admin searches for or selects a user.</p>
<p>2. Admin edits or deactivates the account.</p>
<p>3. The system applies the change and logs it.</p></th>
</tr>
<tr class="header">
<th>Alternative Flow</th>
<th>None.</th>
</tr>
<tr class="odd">
<th>Exception Flow</th>
<th>E1: Attempt to deactivate the only remaining Admin system blocks the action.</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

<table>
<colgroup>
<col style="width: 25%" />
<col style="width: 75%" />
</colgroup>
<thead>
<tr class="header">
<th>Use Case Name</th>
<th>UC11.2 Assign/Reassign Patient to Doctor</th>
</tr>
<tr class="odd">
<th>Brief Description</th>
<th>Changes a patient's assigned doctor, independent of a specific booking.</th>
</tr>
<tr class="header">
<th>Characteristic of activation</th>
<th>Triggered when the Admin reassigns a patient's care team.</th>
</tr>
<tr class="odd">
<th>Primary Actor</th>
<th>Admin</th>
</tr>
<tr class="header">
<th>Secondary Actor</th>
<th>Patient, Doctor</th>
</tr>
<tr class="odd">
<th>Pre-Condition(s)</th>
<th>The patient has an existing account.</th>
</tr>
<tr class="header">
<th colspan="2">Flow of Event</th>
</tr>
<tr class="odd">
<th>Basic Flow</th>
<th><p>1. Admin selects a patient.</p>
<p>2. Admin selects a new doctor.</p>
<p>3. The system updates the assignment and notifies both parties.</p></th>
</tr>
<tr class="header">
<th>Alternative Flow</th>
<th>None.</th>
</tr>
<tr class="odd">
<th>Exception Flow</th>
<th>None.</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

<table>
<colgroup>
<col style="width: 25%" />
<col style="width: 75%" />
</colgroup>
<thead>
<tr class="header">
<th>Use Case Name</th>
<th>UC11.3 View Audit Logs</th>
</tr>
<tr class="odd">
<th>Brief Description</th>
<th>System-wide activity log review for compliance monitoring.</th>
</tr>
<tr class="header">
<th>Characteristic of activation</th>
<th>Triggered when the Admin opens the audit log screen.</th>
</tr>
<tr class="odd">
<th>Primary Actor</th>
<th>Admin</th>
</tr>
<tr class="header">
<th>Secondary Actor</th>
<th>None</th>
</tr>
<tr class="odd">
<th>Pre-Condition(s)</th>
<th>Logged activity exists.</th>
</tr>
<tr class="header">
<th colspan="2">Flow of Event</th>
</tr>
<tr class="odd">
<th>Basic Flow</th>
<th><p>1. Admin opens audit logs.</p>
<p>2. System displays system-wide events, filterable by user/date/action.</p></th>
</tr>
<tr class="header">
<th>Alternative Flow</th>
<th>None.</th>
</tr>
<tr class="odd">
<th>Exception Flow</th>
<th>None.</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

<table>
<colgroup>
<col style="width: 25%" />
<col style="width: 75%" />
</colgroup>
<thead>
<tr class="header">
<th>Use Case Name</th>
<th>UC11.4 Oversee Delivery Orders</th>
</tr>
<tr class="odd">
<th>Brief Description</th>
<th>Monitors medication delivery operations across all patients.</th>
</tr>
<tr class="header">
<th>Characteristic of activation</th>
<th>Triggered when the Admin opens the delivery oversight screen.</th>
</tr>
<tr class="odd">
<th>Primary Actor</th>
<th>Admin</th>
</tr>
<tr class="header">
<th>Secondary Actor</th>
<th>Pharmacist</th>
</tr>
<tr class="odd">
<th>Pre-Condition(s)</th>
<th>At least one recurring medication order exists (Module 13).</th>
</tr>
<tr class="header">
<th colspan="2">Flow of Event</th>
</tr>
<tr class="odd">
<th>Basic Flow</th>
<th><p>1. Admin opens delivery oversight.</p>
<p>2. The system displays order/delivery statuses across patients.</p></th>
</tr>
<tr class="header">
<th>Alternative Flow</th>
<th>None.</th>
</tr>
<tr class="odd">
<th>Exception Flow</th>
<th>E1: Delivery integration (Grab API) unavailable system displays last known status with a stale-data warning.</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

<table>
<colgroup>
<col style="width: 25%" />
<col style="width: 75%" />
</colgroup>
<thead>
<tr class="header">
<th>Use Case Name</th>
<th>UC11.5 Export Hospital-Wide Report</th>
</tr>
<tr class="odd">
<th>Brief Description</th>
<th>Generates a PDF summary report across the hospital's patient population.</th>
</tr>
<tr class="header">
<th>Characteristic of activation</th>
<th>Triggered when the Admin requests a report export.</th>
</tr>
<tr class="odd">
<th>Primary Actor</th>
<th>Admin</th>
</tr>
<tr class="header">
<th>Secondary Actor</th>
<th>None</th>
</tr>
<tr class="odd">
<th>Pre-Condition(s)</th>
<th>Sufficient data exists for the requested reporting period.</th>
</tr>
<tr class="header">
<th colspan="2">Flow of Event</th>
</tr>
<tr class="odd">
<th>Basic Flow</th>
<th><p>1. Admin selects report parameters (date range, scope).</p>
<p>2. The system compiles the report.</p>
<p>3. The system generates and offers the PDF for download.</p></th>
</tr>
<tr class="header">
<th>Alternative Flow</th>
<th>None.</th>
</tr>
<tr class="odd">
<th>Exception Flow</th>
<th>E1: No data in the selected range system notifies the admin instead of generating an empty report.</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

**3.4.12 Module 12 Settings and Preferences**


*Figure 3.37: Use Case Diagram – Module 12: Settings and Preferences*

<table>
<colgroup>
<col style="width: 25%" />
<col style="width: 75%" />
</colgroup>
<thead>
<tr class="header">
<th>Use Case Name</th>
<th>UC12.1 Update Profile/Contact Info</th>
</tr>
<tr class="odd">
<th>Brief Description</th>
<th>Edits account-level contact details from the settings screen.</th>
</tr>
<tr class="header">
<th>Characteristic of activation</th>
<th>Triggered when the Patient edits settings.</th>
</tr>
<tr class="odd">
<th>Primary Actor</th>
<th>Patient</th>
</tr>
<tr class="header">
<th>Secondary Actor</th>
<th>None</th>
</tr>
<tr class="odd">
<th>Pre-Condition(s)</th>
<th>The patient is authenticated.</th>
</tr>
<tr class="header">
<th colspan="2">Flow of Event</th>
</tr>
<tr class="odd">
<th>Basic Flow</th>
<th><p>1. Patient opens Settings.</p>
<p>2. Patient edits contact info.</p>
<p>3. The system saves the update.</p></th>
</tr>
<tr class="header">
<th>Alternative Flow</th>
<th>None.</th>
</tr>
<tr class="odd">
<th>Exception Flow</th>
<th>E1: Invalid input system rejects the save and highlights the field.</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

<table>
<colgroup>
<col style="width: 25%" />
<col style="width: 75%" />
</colgroup>
<thead>
<tr class="header">
<th>Use Case Name</th>
<th>UC12.2 Update Health Profile</th>
</tr>
<tr class="odd">
<th>Brief Description</th>
<th>Edits the onboarding clinical/lifestyle data captured in UC1.4.</th>
</tr>
<tr class="header">
<th>Characteristic of activation</th>
<th>Triggered when the Patient edits their health profile.</th>
</tr>
<tr class="odd">
<th>Primary Actor</th>
<th>Patient</th>
</tr>
<tr class="header">
<th>Secondary Actor</th>
<th>None</th>
</tr>
<tr class="odd">
<th>Pre-Condition(s)</th>
<th>Onboarding (UC1.4) has been completed.</th>
</tr>
<tr class="header">
<th colspan="2">Flow of Event</th>
</tr>
<tr class="odd">
<th>Basic Flow</th>
<th><p>1. The patient opens the health profile section.</p>
<p>2. The patient edits medical history or lifestyle fields.</p>
<p>3. System saves the update and re-triggers Generate Risk Score (UC9.1) if relevant fields changed.</p></th>
</tr>
<tr class="header">
<th>Alternative Flow</th>
<th>None.</th>
</tr>
<tr class="odd">
<th>Exception Flow</th>
<th>None.</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

<table>
<colgroup>
<col style="width: 25%" />
<col style="width: 75%" />
</colgroup>
<thead>
<tr class="header">
<th>Use Case Name</th>
<th>UC12.3 Export Health Data</th>
</tr>
<tr class="odd">
<th>Brief Description</th>
<th>Downloads a copy of the patient's own health data. Also included by Delete Account (UC12.4).</th>
</tr>
<tr class="header">
<th>Characteristic of activation</th>
<th>Triggered when the Patient requests a data export, or automatically offered during account deletion.</th>
</tr>
<tr class="odd">
<th>Primary Actor</th>
<th>Patient</th>
</tr>
<tr class="header">
<th>Secondary Actor</th>
<th>None</th>
</tr>
<tr class="odd">
<th>Pre-Condition(s)</th>
<th>The patient is authenticated.</th>
</tr>
<tr class="header">
<th colspan="2">Flow of Event</th>
</tr>
<tr class="odd">
<th>Basic Flow</th>
<th><p>1. The patient requests an export.</p>
<p>2. The system compiles the patient's data into a downloadable file.</p>
<p>3. The system provides the file to the patient.</p></th>
</tr>
<tr class="header">
<th>Alternative Flow</th>
<th>None.</th>
</tr>
<tr class="odd">
<th>Exception Flow</th>
<th>E1: Export generation fails system notifies the patient and allows retry.</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

<table>
<colgroup>
<col style="width: 25%" />
<col style="width: 75%" />
</colgroup>
<thead>
<tr class="header">
<th>Use Case Name</th>
<th>UC12.4 Delete Account</th>
</tr>
<tr class="odd">
<th>Brief Description</th>
<th>Permanently removes the patient's account. Includes Export Health Data (UC12.3), which is always offered before deletion proceeds.</th>
</tr>
<tr class="header">
<th>Characteristic of activation</th>
<th>Triggered when the Patient requests account deletion.</th>
</tr>
<tr class="odd">
<th>Primary Actor</th>
<th>Patient</th>
</tr>
<tr class="header">
<th>Secondary Actor</th>
<th>None</th>
</tr>
<tr class="odd">
<th>Pre-Condition(s)</th>
<th>The patient is authenticated.</th>
</tr>
<tr class="header">
<th colspan="2">Flow of Event</th>
</tr>
<tr class="odd">
<th>Basic Flow</th>
<th><p>1. Patient requests account deletion.</p>
<p>2. The system offers Export Health Data (UC12.3).</p>
<p>3. Patient confirms deletion.</p>
<p>4. System deactivates and schedules the account and associated data for removal.</p></th>
</tr>
<tr class="header">
<th>Alternative Flow</th>
<th>A1: Patient declines the export and proceeds directly to deletion.</th>
</tr>
<tr class="odd">
<th>Exception Flow</th>
<th>E1: Patient has an active recurring prescription (Module 13) system warns that this will be cancelled before allowing deletion to proceed.</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

**3.4.13 Module 13 Recurring Medication, Payment and Delivery**


*Figure 3.38: Use Case Diagram – Module 13: Recurring Medication, Payment and Delivery*

<table>
<colgroup>
<col style="width: 25%" />
<col style="width: 75%" />
</colgroup>
<thead>
<tr class="header">
<th>Use Case Name</th>
<th>UC13.1 Flag Patient as Recurring</th>
</tr>
<tr class="odd">
<th>Brief Description</th>
<th>Marks a long-term chronic patient for the recurring prescription workflow.</th>
</tr>
<tr class="header">
<th>Characteristic of activation</th>
<th>Triggered when the Doctor enables recurring status for a patient.</th>
</tr>
<tr class="odd">
<th>Primary Actor</th>
<th>Doctor</th>
</tr>
<tr class="header">
<th>Secondary Actor</th>
<th>Patient</th>
</tr>
<tr class="odd">
<th>Pre-Condition(s)</th>
<th>The doctor has issued a prescription for the patient (UC8.4).</th>
</tr>
<tr class="header">
<th colspan="2">Flow of Event</th>
</tr>
<tr class="odd">
<th>Basic Flow</th>
<th><p>1. The doctor selects a patient's prescription.</p>
<p>2. Doctor flags it as recurring.</p>
<p>3. System schedules the monthly Confirm Monthly Order cycle (UC13.2).</p></th>
</tr>
<tr class="header">
<th>Alternative Flow</th>
<th>None.</th>
</tr>
<tr class="odd">
<th>Exception Flow</th>
<th>None.</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

<table>
<colgroup>
<col style="width: 25%" />
<col style="width: 75%" />
</colgroup>
<thead>
<tr class="header">
<th>Use Case Name</th>
<th>UC13.2 Confirm Monthly Order</th>
</tr>
<tr class="odd">
<th>Brief Description</th>
<th>Monthly confirmation prompt for a patient's recurring prescription.</th>
</tr>
<tr class="header">
<th>Characteristic of activation</th>
<th>Triggered automatically on the monthly cycle date.</th>
</tr>
<tr class="odd">
<th>Primary Actor</th>
<th>Patient</th>
</tr>
<tr class="header">
<th>Secondary Actor</th>
<th>System</th>
</tr>
<tr class="odd">
<th>Pre-Condition(s)</th>
<th>The patient is flagged as recurring (UC13.1).</th>
</tr>
<tr class="header">
<th colspan="2">Flow of Event</th>
</tr>
<tr class="odd">
<th>Basic Flow</th>
<th><p>1. The system sends a monthly confirmation prompt.</p>
<p>2. The patient confirms the order.</p>
<p>3. System triggers Select Method &amp; Pay (UC13.3).</p></th>
</tr>
<tr class="header">
<th>Alternative Flow</th>
<th>A1: Patient skips this month's order system pauses the cycle until the next scheduled date.</th>
</tr>
<tr class="odd">
<th>Exception Flow</th>
<th>E1: Patient does not respond within the confirmation window system sends a follow-up reminder.</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

<table>
<colgroup>
<col style="width: 25%" />
<col style="width: 75%" />
</colgroup>
<thead>
<tr class="header">
<th>Use Case Name</th>
<th>UC13.3 Select Method &amp; Pay</th>
</tr>
<tr class="odd">
<th>Brief Description</th>
<th>Choice of self-collection or home delivery plus Stripe payment. Includes into Confirm Monthly Order (UC13.2); always required to confirm an order.</th>
</tr>
<tr class="header">
<th>Characteristic of activation</th>
<th>Triggered immediately after the patient confirms a monthly order.</th>
</tr>
<tr class="odd">
<th>Primary Actor</th>
<th>Patient</th>
</tr>
<tr class="header">
<th>Secondary Actor</th>
<th>System</th>
</tr>
<tr class="odd">
<th>Pre-Condition(s)</th>
<th>The patient has confirmed the monthly order (UC13.2).</th>
</tr>
<tr class="header">
<th colspan="2">Flow of Event</th>
</tr>
<tr class="odd">
<th>Basic Flow</th>
<th><p>1. The patient selects self-collection or home delivery.</p>
<p>2. Patient completes payment via Stripe.</p>
<p>3. The system confirms payment and notifies the pharmacist to prepare the order (UC13.6).</p>
<p>4. If home delivery was selected, the system triggers Dispatch Delivery (UC13.4).</p></th>
</tr>
<tr class="header">
<th>Alternative Flow</th>
<th>None.</th>
</tr>
<tr class="odd">
<th>Exception Flow</th>
<th>E1: Payment declined system notifies the patient and allows retry with an alternate method.</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

<table>
<colgroup>
<col style="width: 25%" />
<col style="width: 75%" />
</colgroup>
<thead>
<tr class="header">
<th>Use Case Name</th>
<th>UC13.4 Dispatch Delivery</th>
</tr>
<tr class="odd">
<th>Brief Description</th>
<th>Grab API dispatch of the prepared medication. Extends Select Method &amp; Pay (UC13.3); fires only when home delivery is chosen.</th>
</tr>
<tr class="header">
<th>Characteristic of activation</th>
<th>Triggered automatically once the pharmacist marks the order Ready for Delivery.</th>
</tr>
<tr class="odd">
<th>Primary Actor</th>
<th>System</th>
</tr>
<tr class="header">
<th>Secondary Actor</th>
<th>Patient</th>
</tr>
<tr class="odd">
<th>Pre-Condition(s)</th>
<th>Home delivery was selected (UC13.3) and the order is ready.</th>
</tr>
<tr class="header">
<th colspan="2">Flow of Event</th>
</tr>
<tr class="odd">
<th>Basic Flow</th>
<th><p>1. The system dispatches the order via the Grab API.</p>
<p>2. The system notifies the patient the delivery is in progress.</p>
<p>3. System triggers Track Delivery Status (UC13.5).</p></th>
</tr>
<tr class="header">
<th>Alternative Flow</th>
<th>None.</th>
</tr>
<tr class="odd">
<th>Exception Flow</th>
<th>E1: Grab API dispatch fails system retries and, if unsuccessful, prompts the patient to switch to self-collection.</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

<table>
<colgroup>
<col style="width: 25%" />
<col style="width: 75%" />
</colgroup>
<thead>
<tr class="header">
<th>Use Case Name</th>
<th>UC13.5 Track Delivery Status</th>
</tr>
<tr class="odd">
<th>Brief Description</th>
<th>Real-time delivery tracking, available once a delivery has been dispatched. Extends Dispatch Delivery (UC13.4).</th>
</tr>
<tr class="header">
<th>Characteristic of activation</th>
<th>Triggered when the Patient opens delivery tracking, available after dispatch.</th>
</tr>
<tr class="odd">
<th>Primary Actor</th>
<th>Patient</th>
</tr>
<tr class="header">
<th>Secondary Actor</th>
<th>System</th>
</tr>
<tr class="odd">
<th>Pre-Condition(s)</th>
<th>A delivery has been dispatched (UC13.4).</th>
</tr>
<tr class="header">
<th colspan="2">Flow of Event</th>
</tr>
<tr class="odd">
<th>Basic Flow</th>
<th><p>1. Patient opens delivery tracking.</p>
<p>2. System displays live status updates from the Grab API.</p></th>
</tr>
<tr class="header">
<th>Alternative Flow</th>
<th>None.</th>
</tr>
<tr class="odd">
<th>Exception Flow</th>
<th>E1: Delivery fails en route system notifies the patient and offers to reschedule or switch to self-collection.</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

<table>
<colgroup>
<col style="width: 25%" />
<col style="width: 75%" />
</colgroup>
<thead>
<tr class="header">
<th>Use Case Name</th>
<th>UC13.6 Prepare Medication</th>
</tr>
<tr class="odd">
<th>Brief Description</th>
<th>The pharmacist prepares the medication order after payment confirmation.</th>
</tr>
<tr class="header">
<th>Characteristic of activation</th>
<th>Triggered automatically once payment is confirmed (UC13.3).</th>
</tr>
<tr class="odd">
<th>Primary Actor</th>
<th>Pharmacist</th>
</tr>
<tr class="header">
<th>Secondary Actor</th>
<th>System</th>
</tr>
<tr class="odd">
<th>Pre-Condition(s)</th>
<th>Payment has been confirmed for an order.</th>
</tr>
<tr class="header">
<th colspan="2">Flow of Event</th>
</tr>
<tr class="odd">
<th>Basic Flow</th>
<th><p>1. The system notifies the pharmacist of a new order.</p>
<p>2. The pharmacist prepares the medication.</p>
<p>3. Pharmacists mark the order Ready for Collection or Ready for Delivery.</p></th>
</tr>
<tr class="header">
<th>Alternative Flow</th>
<th>None.</th>
</tr>
<tr class="odd">
<th>Exception Flow</th>
<th>E1: Medication out of stock pharmacist flags the shortage to the Admin (UC11.4) and notifies the patient of a delay.</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

3.4.14 Symptom Checker and Triage

<table>
<colgroup>
<col style="width: 25%" />
<col style="width: 75%" />
</colgroup>
<thead>
<tr class="header">
<th>Use Case Name</th>
<th>UC14.1 Complete Symptom Checker</th>
</tr>
<tr class="odd">
<th>Brief Description</th>
<th>The patient selects symptoms from a structured hypertension-related list and rates severity.</th>
</tr>
<tr class="header">
<th>Characteristic of activation</th>
<th>Triggered when the Patient opens the Symptom Checker.</th>
</tr>
<tr class="odd">
<th>Primary Actor</th>
<th>Patient</th>
</tr>
<tr class="header">
<th>Secondary Actor</th>
<th>None</th>
</tr>
<tr class="odd">
<th>Pre-Condition(s)</th>
<th>The patient is authenticated.</th>
</tr>
<tr class="header">
<th colspan="2">Flow of Event</th>
</tr>
<tr class="odd">
<th>Basic Flow</th>
<th><p>1. The patient opens the Symptom Checker.</p>
<p>2. The system triggers Capture Heart Rate via PPG (UC14.2).</p>
<p>3. The patient selects symptoms and rates severity (Mild/Moderate/Severe).</p>
<p>4. The patient submits the checker.</p>
<p>5. System triggers Generate Triage Outcome (UC14.3).</p></th>
</tr>
<tr class="header">
<th>Alternative Flow</th>
<th>None.</th>
</tr>
<tr class="odd">
<th>Exception Flow</th>
<th>E1: PPG capture fails system proceeds using symptoms, current BP, and last known risk score only, noting the missing heart rate input.</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

<table>
<colgroup>
<col style="width: 25%" />
<col style="width: 75%" />
</colgroup>
<thead>
<tr class="header">
<th>Use Case Name</th>
<th>UC14.2 Capture Heart Rate via PPG</th>
</tr>
<tr class="odd">
<th>Brief Description</th>
<th>Mandatory heart-rate capture on opening the checker. Includes into Complete Symptom Checker (UC14.1).</th>
</tr>
<tr class="header">
<th>Characteristic of activation</th>
<th>Triggered automatically when the Symptom Checker opens.</th>
</tr>
<tr class="odd">
<th>Primary Actor</th>
<th>Patient</th>
</tr>
<tr class="header">
<th>Secondary Actor</th>
<th>System</th>
</tr>
<tr class="odd">
<th>Pre-Condition(s)</th>
<th>None (same procedure as UC3.3).</th>
</tr>
<tr class="header">
<th colspan="2">Flow of Event</th>
</tr>
<tr class="odd">
<th>Basic Flow</th>
<th><p>1. The system prompts the patient to place a finger over the camera.</p>
<p>2. The system captures and computes heart rate (as per UC3.3).</p></th>
</tr>
<tr class="header">
<th>Alternative Flow</th>
<th>None.</th>
</tr>
<tr class="odd">
<th>Exception Flow</th>
<th>E1: Poor signal system allows the patient to retry or skip.</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

<table>
<colgroup>
<col style="width: 25%" />
<col style="width: 75%" />
</colgroup>
<thead>
<tr class="header">
<th>Use Case Name</th>
<th>UC14.3 Generate Triage Outcome</th>
</tr>
<tr class="odd">
<th>Brief Description</th>
<th>Cross-references symptoms, severity, current BP, heart rate, and ML risk score into a triage result: Monitor at Home, Contact Your Doctor, or Seek Emergency Care. Included into Complete Symptom Checker (UC14.1); performed by System.</th>
</tr>
<tr class="header">
<th>Characteristic of activation</th>
<th>Triggered automatically upon symptom checker submission.</th>
</tr>
<tr class="odd">
<th>Primary Actor</th>
<th>System</th>
</tr>
<tr class="header">
<th>Secondary Actor</th>
<th>Patient</th>
</tr>
<tr class="odd">
<th>Pre-Condition(s)</th>
<th>Symptom checker (UC14.1) has been submitted.</th>
</tr>
<tr class="header">
<th colspan="2">Flow of Event</th>
</tr>
<tr class="odd">
<th>Basic Flow</th>
<th><p>1. System retrieves current BP, heart rate, and latest ML risk score.</p>
<p>2. System cross-references these against the reported symptoms and severity.</p>
<p>3. System classifies the outcome (Mild/Moderate/Emergency per the defined BP and symptom thresholds).</p>
<p>4. The system saves the outcome to the patient's health record.</p>
<p>5. The system triggers Notify Doctor (UC14.4) if the outcome is Moderate or Emergency.</p></th>
</tr>
<tr class="header">
<th>Alternative Flow</th>
<th>None.</th>
</tr>
<tr class="odd">
<th>Exception Flow</th>
<th>None.</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

<table>
<colgroup>
<col style="width: 25%" />
<col style="width: 75%" />
</colgroup>
<thead>
<tr class="header">
<th>Use Case Name</th>
<th>UC14.4 Notify Doctor</th>
</tr>
<tr class="odd">
<th>Brief Description</th>
<th>Automatic doctor notification. Extends Generate Triage Outcome (UC14.3); fires only when the outcome is Moderate or Emergency.</th>
</tr>
<tr class="header">
<th>Characteristic of activation</th>
<th>Triggered automatically when the triage outcome is Moderate or Emergency.</th>
</tr>
<tr class="odd">
<th>Primary Actor</th>
<th>System</th>
</tr>
<tr class="header">
<th>Secondary Actor</th>
<th>Doctor</th>
</tr>
<tr class="odd">
<th>Pre-Condition(s)</th>
<th>A triage outcome of Moderate or Emergency has just been generated.</th>
</tr>
<tr class="header">
<th colspan="2">Flow of Event</th>
</tr>
<tr class="odd">
<th>Basic Flow</th>
<th><p>1. The system composes an urgent notification with the patient's vitals, symptoms, and risk scores.</p>
<p>2. The system sends it to the assigned doctor.</p>
<p>3. In an emergency, the system additionally triggers emergency appointment booking, family alert (UC15.2), and reassigns to the next available doctor if the assigned one is unavailable.</p></th>
</tr>
<tr class="header">
<th>Alternative Flow</th>
<th>None.</th>
</tr>
<tr class="odd">
<th>Exception Flow</th>
<th>None.</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

3.4.15 Family Monitoring and Emergency Alert

<table>
<colgroup>
<col style="width: 25%" />
<col style="width: 75%" />
</colgroup>
<thead>
<tr class="header">
<th>Use Case Name</th>
<th>UC15.1 View Patient Vitals</th>
</tr>
<tr class="odd">
<th>Brief Description</th>
<th>Real-time view of the linked patient's readings and health status.</th>
</tr>
<tr class="header">
<th>Characteristic of activation</th>
<th>Triggered when the Family Member opens the monitoring view.</th>
</tr>
<tr class="odd">
<th>Primary Actor</th>
<th>Family Member</th>
</tr>
<tr class="header">
<th>Secondary Actor</th>
<th>None</th>
</tr>
<tr class="odd">
<th>Pre-Condition(s)</th>
<th>The Family Member account is linked to a patient profile.</th>
</tr>
<tr class="header">
<th colspan="2">Flow of Event</th>
</tr>
<tr class="odd">
<th>Basic Flow</th>
<th><p>1. Family Member opens the app.</p>
<p>2. The system displays the linked patient's current vitals and status.</p></th>
</tr>
<tr class="header">
<th>Alternative Flow</th>
<th>None.</th>
</tr>
<tr class="odd">
<th>Exception Flow</th>
<th>E1: Patient has not granted/linked access system displays a pending-link state.</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

<table>
<colgroup>
<col style="width: 25%" />
<col style="width: 75%" />
</colgroup>
<thead>
<tr class="header">
<th>Use Case Name</th>
<th>UC15.2 Send Emergency Alert to Family</th>
</tr>
<tr class="odd">
<th>Brief Description</th>
<th>Automated notification to linked family members when the patient's risk reaches Critical.</th>
</tr>
<tr class="header">
<th>Characteristic of activation</th>
<th>Triggered automatically by Escalate to Doctor/Family (UC9.3) or Notify Doctor (UC14.4) when risk is Critical.</th>
</tr>
<tr class="odd">
<th>Primary Actor</th>
<th>System</th>
</tr>
<tr class="header">
<th>Secondary Actor</th>
<th>Family Member</th>
</tr>
<tr class="odd">
<th>Pre-Condition(s)</th>
<th>At least one family member is linked to the patient.</th>
</tr>
<tr class="header">
<th colspan="2">Flow of Event</th>
</tr>
<tr class="odd">
<th>Basic Flow</th>
<th><p>1. The system detects a Critical risk event.</p>
<p>2. The system sends an emergency alert with the patient's live GPS location to all linked family members.</p></th>
</tr>
<tr class="header">
<th>Alternative Flow</th>
<th>None.</th>
</tr>
<tr class="odd">
<th>Exception Flow</th>
<th>E1: No family member linked, system logs the event and relies solely on doctor/emergency escalation.</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

<table>
<colgroup>
<col style="width: 25%" />
<col style="width: 75%" />
</colgroup>
<thead>
<tr class="header">
<th>Use Case Name</th>
<th>UC15.3 Enable GPS Tracking &amp; Emergency Call</th>
</tr>
<tr class="odd">
<th>Brief Description</th>
<th>GPS tracking and one-tap emergency call, available only after an emergency alert has been received. Extends Send Emergency Alert to Family (UC15.2).</th>
</tr>
<tr class="header">
<th>Characteristic of activation</th>
<th>Triggered automatically as soon as the family member receives an emergency alert.</th>
</tr>
<tr class="odd">
<th>Primary Actor</th>
<th>Family Member</th>
</tr>
<tr class="header">
<th>Secondary Actor</th>
<th>System</th>
</tr>
<tr class="odd">
<th>Pre-Condition(s)</th>
<th>An emergency alert (UC15.2) has just been received.</th>
</tr>
<tr class="header">
<th colspan="2">Flow of Event</th>
</tr>
<tr class="odd">
<th>Basic Flow</th>
<th><p>1. The system unlocks live GPS tracking and the one-tap emergency call button on the family member's view.</p>
<p>2. Family Members may track the patient's location.</p>
<p>3. Family Members may use the one-tap button to call emergency services or the patient directly.</p></th>
</tr>
<tr class="header">
<th>Alternative Flow</th>
<th>None.</th>
</tr>
<tr class="odd">
<th>Exception Flow</th>
<th>None.</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

##  

##  

## **3.5 Activity Diagram**

**3.5.1 Module 1: Register Account**


*Figure 3.39: Activity Diagram – Module 1: Register Account*

**3.5.2 Module 2: View Health Summary Dashboard**


*Figure 3.40: Activity Diagram – Module 2: View Health Summary Dashboard*

**3.5.3 Module 3: Log Blood Pressure Reading**


*Figure 3.41: Activity Diagram – Module 3: Log Blood Pressure Reading*

**3.5.4 Module 4: View BP Trend & Compare Vitals**


*Figure 3.42: Activity Diagram – Module 4: View BP Trend & Compare Vitals*

**3.5.5 Module 5: Manage Medication List**


*Figure 3.43: Activity Diagram – Module 5: Manage Medication List*

**3.5.6 Module 6: Upload & Share Health Record**


*Figure 3.44: Activity Diagram – Module 6: Upload & Share Health Record*

**3.5.7 Module 7: Book & Reschedule Appointment**


*Figure 3.45: Activity Diagram – Module 7: Book & Reschedule Appointment*

**3.5.8 Module 8: Review Patient & Write Note**


*Figure 3.46: Activity Diagram – Module 8: Review Patient & Write Note*

**3.5.9 Module 9: Generate Risk Score & Escalate**


*Figure 3.47: Activity Diagram – Module 9: Generate Risk Score & Escalate*

**3.5.10 Module 10: Send Secure Message & Escalate**


*Figure 3.48: Activity Diagram – Module 10: Send Secure Message & Escalate*

**3.5.11 Module 11: Admin Account & Oversight Flow**


*Figure 3.49: Activity Diagram – Module 11: Admin Account & Oversight Flow*

**3.5.12 Module 12: Update Profile, Export & Delete**


*Figure 3.50: Activity Diagram – Module 12: Update Profile, Export & Delete*

**3.5.13 Module 13: Confirm Order, Pay & Dispatch**


*Figure 3.51: Activity Diagram – Module 13: Confirm Order, Pay & Dispatch*

**3.5.14 Symptom Checker & Triage**


*Figure 3.52: Activity Diagram – Symptom Checker & Triage*

**3.5.15 Family Monitoring & Emergency Alert**


*Figure 3.53: Activity Diagram – Family Monitoring & Emergency Alert*

## **3.6 Functional Requirements**

Module 1: User and Access Management

| ID     | Requirement Description                                                                                                                                                                                                                           |
|--------|---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| FR-1.1 | The system shall allow patients and family members to self-register a new account using email/password via Firebase Authentication. Doctor, Pharmacist, and Admin accounts are provisioned by the Admin rather than self-registered (see FR-1.6). |
| FR-1.2 | The system shall allow all registered users, regardless of role, to log in and log out using email/password via Firebase Authentication.                                                                                                          |
| FR-1.3 | The system shall enforce role-based access control for Patient, Doctor, Family Member, Pharmacist, and Admin roles.                                                                                                                               |
| FR-1.4 | The system shall require patients to complete a one-time onboarding health profile covering personal information, medical history, and lifestyle, immediately after their first registration.                                                     |
| FR-1.5 | The system shall log all user activity for audit purposes.                                                                                                                                                                                        |
| FR-1.6 | The system shall allow only the Admin to create Doctor, Pharmacist, and Admin accounts; these roles shall have no self-registration access of their own.                                                                                          |

Module 2: Patient Health Overview

| ID     | Requirement Description                                                                                                                               |
|--------|-------------------------------------------------------------------------------------------------------------------------------------------------------|
| FR-2.1 | The system shall display a personalised dashboard summarising medication schedule, upcoming appointments, recent BP readings, and current risk score. |
| FR-2.2 | The system shall provide quick-access navigation to vitals logging, symptom checker, messaging, and the AI Health Agent.                              |

Module 3: Vital Signs Tracking

| ID     | Requirement Description                                                                      |
|--------|----------------------------------------------------------------------------------------------|
| FR-3.1 | The system shall allow patients to manually log blood pressure readings with optional notes. |
| FR-3.2 | The system shall capture heart rate via mobile camera PPG (Yan et al., 2017).                |

Module 4: Health Data Visualisation

| ID     | Requirement Description                                                                       |
|--------|-----------------------------------------------------------------------------------------------|
| FR-4.1 | The system shall display BP trend charts across 7-day, 30-day, 3-month, and 1-year views.     |
| FR-4.2 | The system shall display statistical summaries (average, minimum, maximum) for logged vitals. |
| FR-4.3 | The system shall display disease risk score trends over time.                                 |

Module 5: Medication Management

| ID     | Requirement Description                                                                        |
|--------|------------------------------------------------------------------------------------------------|
| FR-5.1 | The system shall allow patients to add, edit, and delete medications with dosage and schedule. |
| FR-5.2 | The system shall send push notification reminders for scheduled doses.                         |
| FR-5.3 | The system shall log missed doses and compute a running adherence rate.                        |
| FR-5.4 | The system shall send refill and drug interaction alerts.                                      |

Module 6: Health Records Management

| ID     | Requirement Description                                                        |
|--------|--------------------------------------------------------------------------------|
| FR-6.1 | The system shall allow patients to upload and categorise medical documents.    |
| FR-6.2 | The system shall allow patients to share documents with their assigned doctor. |

Module 7: Appointment Scheduling

| ID     | Requirement Description                                                                                |
|--------|--------------------------------------------------------------------------------------------------------|
| FR-7.1 | The system shall allow patients to book, reschedule, and cancel appointments.                          |
| FR-7.2 | The system shall allow the Admin to assign a doctor to a patient upon booking.                         |
| FR-7.3 | The system shall send appointment reminders via push notification and email.                           |
| FR-7.4 | The system shall generate a pre-visit summary before each appointment.                                 |
| FR-7.5 | The system shall prompt the patient to book an appointment when disease risk reaches High or Critical. |

Module 8: Healthcare Provider Portal

| ID     | Requirement Description                                                                                                 |
|--------|-------------------------------------------------------------------------------------------------------------------------|
| FR-8.1 | The system shall display only the doctor's assigned patient list, searchable and filterable by ML-predicted risk level. |
| FR-8.2 | The system shall allow doctors to view full health history for assigned patients.                                       |
| FR-8.3 | The system shall allow doctors to write clinical notes, update care plans, and issue prescriptions.                     |
| FR-8.4 | The system shall deliver risk alerts, triage notifications, and deterioration alerts to the assigned doctor.            |

Module 9: AI-Powered Health Monitoring

| ID     | Requirement Description                                                                                                                                                                                          |
|--------|------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| FR-9.1 | The system shall generate real-time threshold alerts for critically out-of-range BP readings.                                                                                                                    |
| FR-9.2 | The system shall predict patient risk for Stroke, Coronary Artery Disease, Heart Failure, Chronic Kidney Disease, and Type 2 Diabetes using Random Forest/XGBoost models (Breiman, 2001; Chen & Guestrin, 2016). |
| FR-9.3 | The system shall categorise each risk score as Low, Moderate, High, or Critical.                                                                                                                                 |
| FR-9.4 | The system shall auto-generate personalized recommendations based on risk level.                                                                                                                                 |
| FR-9.5 | The system shall notify the assigned doctor when patient risk escalates, and family members when risk reaches Critical.                                                                                          |
| FR-9.6 | The system shall send a deterioration alert to the doctor when risk worsens steadily over 30 days.                                                                                                               |

Module 10: Care Coordination and Messaging

| ID      | Requirement Description                                                                       |
|---------|-----------------------------------------------------------------------------------------------|
| FR-10.1 | The system shall provide secure messaging between patients and their assigned doctor.         |
| FR-10.2 | The system shall provide shared care plan access across the assigned care team.               |
| FR-10.3 | The system shall auto-escalate messages containing high-risk keywords to the assigned doctor. |

Module 11: Admin Panel

| ID      | Requirement Description                                                                                           |
|---------|-------------------------------------------------------------------------------------------------------------------|
| FR-11.1 | The system shall allow the Admin to manage all user accounts (view, edit, deactivate).                            |
| FR-11.2 | The system shall allow the Admin to assign and reassign patients to doctors.                                      |
| FR-11.3 | The system shall provide audit log access and system health monitoring.                                           |
| FR-11.4 | The system shall allow the Admin to oversee medication delivery orders and generate hospital-wide reports as PDF. |

Module 12: Settings and Preferences

| ID      | Requirement Description                                                                                |
|---------|--------------------------------------------------------------------------------------------------------|
| FR-12.1 | The system shall allow patients to update profile, contact information, and onboarding health profile. |
| FR-12.2 | The system shall allow patients to export their health data or delete their account.                   |

Module 13: Recurring Medication, Payment and Delivery

| ID      | Requirement Description                                                                                                                    |
|---------|--------------------------------------------------------------------------------------------------------------------------------------------|
| FR-13.1 | The system shall allow doctors to flag a patient as long-term chronic and issue a recurring prescription.                                  |
| FR-13.2 | The system shall automatically notify the patient monthly to confirm their medication order.                                               |
| FR-13.3 | The system shall process payment via Stripe and notify the pharmacist upon confirmation.                                                   |
| FR-13.4 | The system shall support self-collection (with collection slip) and home delivery (via Grab API with real-time tracking) fulfilment paths. |
| FR-13.5 | The system shall prompt the patient to reschedule or switch the collection method upon failed delivery.                                    |

Cross-Cutting Features

| ID      | Requirement Description                                                                                                                                                                                |
|---------|--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| FR-14.1 | (AI Health Agent) The system shall provide a 24/7 conversational agent, powered by Google Gemini Flash, that answers patient queries and explains risk scores in plain language.                       |
| FR-14.2 | (Family Monitoring) The system shall allow linked family members to view real-time BP readings and receive Critical-level emergency alerts with GPS location.                                          |
| FR-14.3 | (Symptom Checker and Triage) The system shall cross-reference symptoms, severity, vitals, and risk scores to produce a triage outcome of Monitor at Home, Contact Your Doctor, or Seek Emergency Care. |
| FR-14.4 | (NLP Message Analysis) The system shall scan patient messages for high-risk keywords and auto-escalate flagged messages.                                                                               |

**3.7 Non-Functional Requirements**

3.7.1 Performance

| ID      | Requirement Description                                                                                                                                           |
|---------|-------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| NFR-1.1 | BP readings and messages shall synchronise across connected clients within 2 seconds under normal network conditions, leveraging Firestore's real-time listeners. |
| NFR-1.2 | ML risk prediction inference shall return a result within 3 seconds of request.                                                                                   |

3.7.2 Security

| ID      | Requirement Description                                                                                                                                                                          |
|---------|--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| NFR-2.1 | All patient-doctor messaging shall be end-to-end encrypted.                                                                                                                                      |
| NFR-2.2 | Role-based access control shall be enforced at the database level via Firestore security rules, ensuring patients can access only their own data and doctors only their assigned patients' data. |
| NFR-2.3 | All payment processing shall comply with PCI DSS via Stripe.                                                                                                                                     |
| NFR-2.4 | All data transmission shall occur over HTTPS.                                                                                                                                                    |

3.7.3 Usability

| ID      | Requirement Description                                                                                                                                     |
|---------|-------------------------------------------------------------------------------------------------------------------------------------------------------------|
| NFR-3.1 | The mobile application interface shall be usable by patients with limited digital literacy, supported by the AI Health Agent's plain-language explanations. |
| NFR-3.2 | Each user role shall be presented with a role-specific interface limited to functions relevant to that role.                                                |

3.7.4 Reliability and Availability

| ID      | Requirement Description                                                                                                                                    |
|---------|------------------------------------------------------------------------------------------------------------------------------------------------------------|
| NFR-4.1 | The system shall maintain 99% uptime, leveraging Firebase's managed, auto-scaling infrastructure.                                                          |
| NFR-4.2 | The mobile application shall retain offline access to previously loaded data via Firestore's offline persistence, syncing automatically upon reconnection. |

3.7.5 Scalability

| ID      | Requirement Description                                                                                                                                                                     |
|---------|---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| NFR-5.1 | The backend shall support horizontal scaling of concurrent users without requiring architectural change, via Firebase's managed infrastructure and FastAPI's asynchronous request handling. |

3.7.6 Compatibility

| ID      | Requirement Description                                                                                                   |
|---------|---------------------------------------------------------------------------------------------------------------------------|
| NFR-6.1 | The mobile application shall be compatible with Android devices running \[INSERT: minimum Android API level\].            |
| NFR-6.2 | The Healthcare Provider Portal and Admin Panel shall be accessible via modern web browsers through the Flutter web build. |

3.7.7 Maintainability

| ID      | Requirement Description                                                                                                                           |
|---------|---------------------------------------------------------------------------------------------------------------------------------------------------|
| NFR-7.1 | The codebase shall follow a modular architecture aligned to the thirteen system modules, allowing individual modules to be updated independently. |

3.7.8 Compliance

| ID      | Requirement Description                                                                                                                                                                                                                                                                       |
|---------|-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| NFR-8.1 | The system shall handle patient health data in accordance with Malaysia's Personal Data Protection Act (PDPA) principles, including purpose limitation and data minimisation, given the platform's academic proof-of-concept status noted in Section 1.6 (Personal Data Protection Act 2010). |

##  

## **3.8 Chapter Summary**

This chapter set out the methodology used to design and specify the hypertension care management platform, and presented the requirement analysis that grounds the system's scope. The Incremental Development model was adopted as the system development methodology (Section 3.1), selected over Waterfall, Prototyping, and Agile Scrum because it balances structured, auditable documentation with the practicality of a solo development context, while still allowing high-priority modules to be delivered and tested early.

Requirements were gathered through two complementary techniques: a semi-structured patient interview and a public online questionnaire (Section 3.2), chosen so that depth of insight from direct patient experience could be triangulated against breadth of evidence from a much larger respondent pool. The absence of a clinician interview was acknowledged as a limitation of this process and is revisited in Chapter 5 as a priority for future work.

The requirement analysis (Section 3.3) confirmed the platform's three core problem domains – monitoring, adherence, and coordination – are genuine and widespread rather than assumed. The interview with Patient Daniel surfaced recurring themes around irregular monitoring habits, schedule-driven non-adherence, data-privacy concerns, and a preference for in-app doctor communication over phone calls. The questionnaire (n = 121) reinforced these findings at scale: a large share of respondents rarely or never check their blood pressure, a meaningful proportion of medicated respondents forget or skip doses regularly, and the two most sought-after proposed features – the 24/7 AI chat assistant and the symptom checker – were both AI-driven decision-support tools rather than passive logging tools, supporting their treatment as core differentiators of the platform rather than secondary additions.

These findings were translated into thirteen system modules and four cross-cutting features, each specified through use case diagrams and detailed use case descriptions covering primary and secondary actors, preconditions, basic and alternative flows, and exception handling (Section 3.4), and further illustrated through activity diagrams showing the step-by-step logic of each module's key workflows (Section 3.5). From these, 26 functional requirements were derived across the thirteen modules and four cross-cutting features (Section 3.6), alongside non-functional requirements spanning performance, security, usability, reliability, scalability, compatibility, maintainability, and compliance with Malaysia's Personal Data Protection Act (Section 3.7).

Together, this methodology and requirement set form the foundation for the system design and architecture presented in the next chapter.

##  

## **3.9 Reference**

> 1\. Braun, V., & Clarke, V. (2006). Using thematic analysis in psychology. Qualitative Research in Psychology, 3(2), 77–101. https://doi.org/10.1191/1478088706qp063oa
>
> 2.Breiman, L. (2001). Random forests. Machine Learning, 45(1), 5–32. https://doi.org/10.1023/A:1010933404324
>
> 3\. Chen, T., & Guestrin, C. (2016). XGBoost: A scalable tree boosting system. In Proceedings of the 22nd ACM SIGKDD International Conference on Knowledge Discovery and Data Mining (pp. 785–794). Association for Computing Machinery. https://doi.org/10.1145/2939672.2939785
>
> 4\. DeJonckheere, M., & Vaughn, L. M. (2019). Semistructured interviewing in primary care research: A balance of relationship and rigour. Family Medicine and Community Health, 7(2), e000057. https://doi.org/10.1136/fmch-2018-000057
>
> 5.Personal Data Protection Act 2010 (Act 709) (Malaysia). https://www.pdp.gov.my/ppdpv1/en/akta/pdp-act-2010-en/
>
> 6\. Royce, W. W. (1970). Managing the development of large software systems. Proceedings of IEEE WESCON, 26, 328–388.
>
> 7\. Schwaber, K., & Sutherland, J. (2020). The Scrum Guide: The definitive guide to Scrum: The rules of the game. Scrum.org. https://www.scrumguides.org/scrum-guide.html
>
> 8\. Sommerville, I. (2016). Software engineering (10th ed.). Pearson Education Limited.
>
> 9\. Yan, B. P., Chan, C. K. Y., Li, C. K. H., To, O. T. L., Lai, W. H. S., Tse, G., Poh, Y. C., & Poh, M. Z. (2017). Resting and postexercise heart rate detection from fingertip and facial photoplethysmography using a smartphone camera: A validation study. JMIR mHealth and uHealth, 5(3), e33. https://doi.org/10.2196/mhealth.7275
