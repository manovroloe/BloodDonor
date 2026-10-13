/** pages/donor-registration: extracted from the working v22 flows. No build step is required. */
import { $, $$, esc, fmt, loading, normalizePhone, toast, today } from '../core/dom.js';
import { sb } from '../core/client.js';
import { query } from '../core/routing.js';
import { showReceipt } from '../components/feedback.js';
import { profileState } from './profile.js';
function donorAge(value) {
    if (!value)
        return null;
    const d = new Date(value + 'T00:00:00'), n = new Date();
    let a = n.getFullYear() - d.getFullYear();
    const m = n.getMonth() - d.getMonth();
    if (m < 0 || (m === 0 && n.getDate() < d.getDate()))
        a--;
    return a;
}
const donorPolicy = {
    donation_interval_days: 90, body_mod_wait_months: 12, alcohol_wait_hours: 24, nicotine_wait_hours: 4
};
const donorPermanentLabels = {
    hiv: 'HIV / AIDS', hepatitis_b: 'Hepatitis B', hepatitis_c: 'Hepatitis C', syphilis: 'Syphilis', blood_cancer: 'Leukemia / lymphoma', active_malignancy: 'Active malignant cancer', iv_drug_use: 'Recreational injected drug use'
};
const donorReviewLabels = {
    heart_disease: 'Serious heart disease', severe_lung: 'Severe lung disease', kidney_disease: 'Severe kidney disease', neurologic_psych: 'Neurologic / psychiatric condition affecting donation safety', other_chronic: 'Other serious chronic condition'
};
const donorQuizAnswers = {
    birth_date: '', weight_kg: '', current_illness: false, on_antibiotics: false, permanent_conditions: [], review_conditions: [], medication_current: false, medication_details: '', has_tattoo: 'false', tattoo_date: '', has_piercing: 'false', piercing_date: '', has_acupuncture: 'false', acupuncture_date: '', pregnancy_status: 'not_applicable', postpartum_date: '', breastfeeding: false, alcohol_last_24h: false, last_alcohol_at: '', smokes: false, last_nicotine_at: '', other_habits: '', donated_before: false, last_donation_date: ''
};
let donorQuizStep = 0, donorQuizOutcome = '';
const yesNoChoices = (name, value, yesText = 'Yes', noText = 'No') => `<div class="quiz-choice-grid"><label class="quiz-choice"><input type="radio" name="${name}" value="false" ${value !== true ? 'checked' : ''}><span><b>${noText}</b></span></label><label class="quiz-choice"><input type="radio" name="${name}" value="true" ${value === true ? 'checked' : ''}><span><b>${yesText}</b></span></label></div>`;
const checklist = (name, items, selected = []) => `<div class="quiz-choice-grid quiz-checklist">${Object.entries(items).map(([v, label]) => `<label class="quiz-choice"><input type="checkbox" name="${name}" value="${v}" ${selected.includes(v) ? 'checked' : ''}><span><b>${esc(label)}</b></span></label>`).join('')}</div>`;
const toLocalDateTimeValue = value => {
    if (!value)
        return '';
    const d = new Date(value);
    if (Number.isNaN(d.getTime()))
        return String(value).slice(0, 16);
    const z = n => String(n).padStart(2, '0');
    return `${d.getFullYear()}-${z(d.getMonth() + 1)}-${z(d.getDate())}T${z(d.getHours())}:${z(d.getMinutes())}`;
};
const addBodyModWait = value => {
    if (!value)
        return null;
    const d = new Date(value + 'T00:00:00');
    d.setFullYear(d.getFullYear() + 1);
    return d;
};
const maxDate = (a, b) => !a ? b : !b ? a : (a > b ? a : b);
async function loadDonorScreeningPolicy() {
    if (!sb)
        return;
    const { data, error } = await sb.rpc('donor_screening_policy');
    if (!error && data && typeof data === 'object')
        Object.assign(donorPolicy, data);
}
const donorQuizSteps = [
    {
        title: 'How old are you?', help: 'Enter your birth date. BloodCare checks the 18–65 age requirement before continuing.', render: () => `<div class="quiz-input-group"><label for="quizBirthDate">Birth date</label><input id="quizBirthDate" type="date" value="${esc(donorQuizAnswers.birth_date)}" max="${today()}"></div>`
    },
    {
        title: 'What is your current weight?', help: 'The BloodCare pre-screen requires a minimum weight of 50 kg.', render: () => `<div class="quiz-input-group"><label for="quizWeight">Weight in kilograms</label><div class="quiz-number-wrap"><input id="quizWeight" type="number" min="1" max="300" step="0.1" value="${esc(donorQuizAnswers.weight_kg)}"><span>kg</span></div></div>`
    },
    {
        title: 'Are you currently unwell or taking antibiotics?', help: 'Active fever, flu, infection, or treatment for an infection normally requires temporary deferral until recovery.', render: () => `<div class="quiz-subquestion"><b>Current fever, flu, infection, or other active illness?</b>${yesNoChoices('quizIllness', donorQuizAnswers.current_illness)}</div><div class="quiz-subquestion"><b>Currently taking antibiotics for an infection or still completing a course?</b>${yesNoChoices('quizAntibiotics', donorQuizAnswers.on_antibiotics)}</div>`
    },
    {
        title: 'Medical history check', help: 'Select anything that applies. Some answers stop online clearance; others require trained staff or medical review.', render: () => `<div class="quiz-group-label">Conditions that stop online clearance</div>${checklist('quizPermanent', donorPermanentLabels, donorQuizAnswers.permanent_conditions)}<div class="quiz-group-label">Conditions requiring staff / medical review</div>${checklist('quizReview', donorReviewLabels, donorQuizAnswers.review_conditions)}<small class="quiz-helper">Leave all boxes unchecked if none apply.</small>`
    },
    {
        title: 'Are you currently taking medication?', help: 'Medication does not automatically reject you, but some medicines require staff review before donation.', render: () => `${yesNoChoices('quizMedication', donorQuizAnswers.medication_current)}<div id="quizMedicationWrap" class="quiz-input-group quiz-followup" ${donorQuizAnswers.medication_current ? '' : 'hidden'}><label for="quizMedicationDetails">Medication name(s) and reason</label><textarea id="quizMedicationDetails" rows="4" ${donorQuizAnswers.medication_current ? '' : 'disabled'} placeholder="Example: warfarin, isotretinoin, antibiotics, maintenance medication…">${esc(donorQuizAnswers.medication_details)}</textarea></div>`
    },
    {
        title: 'Have you had a tattoo?', help: `A conservative BloodCare pre-screen uses a ${donorPolicy.body_mod_wait_months || 12}-month waiting period after the most recent tattoo.`, render: () => `${yesNoChoices('quizTattoo', donorQuizAnswers.has_tattoo === 'true')}<div id="quizTattooDateWrap" class="quiz-input-group quiz-followup" ${donorQuizAnswers.has_tattoo === 'true' ? '' : 'hidden'}><label for="quizTattooDate">Most recent tattoo date</label><input id="quizTattooDate" type="date" value="${esc(donorQuizAnswers.tattoo_date)}" max="${today()}" ${donorQuizAnswers.has_tattoo === 'true' ? '' : 'disabled'}></div>`
    },
    {
        title: 'Have you had a body or ear piercing?', help: `A conservative BloodCare pre-screen uses the same ${donorPolicy.body_mod_wait_months || 12}-month waiting period after the most recent piercing.`, render: () => `${yesNoChoices('quizPiercing', donorQuizAnswers.has_piercing === 'true')}<div id="quizPiercingDateWrap" class="quiz-input-group quiz-followup" ${donorQuizAnswers.has_piercing === 'true' ? '' : 'hidden'}><label for="quizPiercingDate">Most recent piercing date</label><input id="quizPiercingDate" type="date" value="${esc(donorQuizAnswers.piercing_date)}" max="${today()}" ${donorQuizAnswers.has_piercing === 'true' ? '' : 'disabled'}></div>`
    },
    {
        title: 'Have you had acupuncture?', help: `If yes, BloodCare applies the same conservative ${donorPolicy.body_mod_wait_months || 12}-month body-modification waiting period for online pre-screening.`, render: () => `${yesNoChoices('quizAcupuncture', donorQuizAnswers.has_acupuncture === 'true')}<div id="quizAcupunctureDateWrap" class="quiz-input-group quiz-followup" ${donorQuizAnswers.has_acupuncture === 'true' ? '' : 'hidden'}><label for="quizAcupunctureDate">Most recent acupuncture date</label><input id="quizAcupunctureDate" type="date" value="${esc(donorQuizAnswers.acupuncture_date)}" max="${today()}" ${donorQuizAnswers.has_acupuncture === 'true' ? '' : 'disabled'}></div>`
    },
    {
        title: 'Pregnancy and recent childbirth', help: 'Pregnancy and recent childbirth require temporary deferral. Breastfeeding or individual postpartum circumstances require staff review.', render: () => `<div class="quiz-choice-grid"><label class="quiz-choice"><input type="radio" name="quizPregnancy" value="not_applicable" ${donorQuizAnswers.pregnancy_status === 'not_applicable' ? 'checked' : ''}><span><b>Not applicable</b></span></label><label class="quiz-choice"><input type="radio" name="quizPregnancy" value="no" ${donorQuizAnswers.pregnancy_status === 'no' ? 'checked' : ''}><span><b>No</b><small>Not pregnant / no recent childbirth.</small></span></label><label class="quiz-choice"><input type="radio" name="quizPregnancy" value="pregnant" ${donorQuizAnswers.pregnancy_status === 'pregnant' ? 'checked' : ''}><span><b>Currently pregnant</b></span></label><label class="quiz-choice"><input type="radio" name="quizPregnancy" value="recent_birth" ${donorQuizAnswers.pregnancy_status === 'recent_birth' ? 'checked' : ''}><span><b>Recent childbirth</b></span></label></div><div id="quizPostpartumWrap" class="quiz-input-group quiz-followup" ${donorQuizAnswers.pregnancy_status === 'recent_birth' ? '' : 'hidden'}><label for="quizPostpartumDate">Delivery date</label><input id="quizPostpartumDate" type="date" value="${esc(donorQuizAnswers.postpartum_date)}" max="${today()}" ${donorQuizAnswers.pregnancy_status === 'recent_birth' ? '' : 'disabled'}></div><label class="quiz-inline-check"><input id="quizBreastfeeding" type="checkbox" ${donorQuizAnswers.breastfeeding ? 'checked' : ''}> Currently breastfeeding</label>`
    },
    {
        title: 'Have you consumed alcohol in the past 24 hours?', help: `BloodCare uses a ${donorPolicy.alcohol_wait_hours || 24}-hour alcohol-free period before donation because alcohol can contribute to dehydration and fainting risk.`, render: () => `${yesNoChoices('quizAlcohol', donorQuizAnswers.alcohol_last_24h)}<div id="quizAlcoholWrap" class="quiz-input-group quiz-followup" ${donorQuizAnswers.alcohol_last_24h ? '' : 'hidden'}><label for="quizAlcoholTime">When was your last alcoholic drink?</label><input id="quizAlcoholTime" type="datetime-local" value="${esc(toLocalDateTimeValue(donorQuizAnswers.last_alcohol_at))}" max="${toLocalDateTimeValue(new Date().toISOString())}" ${donorQuizAnswers.alcohol_last_24h ? '' : 'disabled'}></div>`
    },
    {
        title: 'Do you currently smoke or vape nicotine?', help: `Smoking or vaping does not permanently disqualify you. BloodCare uses a ${donorPolicy.nicotine_wait_hours || 4}-hour buffer before donation for the online pre-screen.`, render: () => `${yesNoChoices('quizNicotine', donorQuizAnswers.smokes)}<div id="quizNicotineWrap" class="quiz-input-group quiz-followup" ${donorQuizAnswers.smokes ? '' : 'hidden'}><label for="quizNicotineTime">When did you last smoke or vape?</label><input id="quizNicotineTime" type="datetime-local" value="${esc(toLocalDateTimeValue(donorQuizAnswers.last_nicotine_at))}" max="${toLocalDateTimeValue(new Date().toISOString())}" ${donorQuizAnswers.smokes ? '' : 'disabled'}></div><div class="quiz-input-group"><label for="quizOtherHabits">Other lifestyle note</label><input id="quizOtherHabits" value="${esc(donorQuizAnswers.other_habits)}" placeholder="Optional"></div>`
    },
    {
        title: 'Have you donated blood before?', help: `If yes, enter the most recent donation date. BloodCare currently uses a ${donorPolicy.donation_interval_days || 90}-day interval before the next donation, subject to staff confirmation.`, render: () => `${yesNoChoices('quizDonatedBefore', donorQuizAnswers.donated_before)}<div id="quizLastDonationWrap" class="quiz-input-group quiz-followup" ${donorQuizAnswers.donated_before ? '' : 'hidden'}><label for="quizLastDonationDate">Most recent donation date</label><input id="quizLastDonationDate" type="date" value="${esc(donorQuizAnswers.last_donation_date)}" max="${today()}" ${donorQuizAnswers.donated_before ? '' : 'disabled'}></div>`
    }
];
function donorQuizError(message = '') {
    const el = $('#donorQuizError');
    if (!el)
        return;
    el.textContent = message;
    el.hidden = !message;
}
function bindDonorQuizFollowups() {
    const bind = (name, wrapId, inputId, truth = 'true') => {
        const sync = () => {
            const on = $(`input[name="${name}"]:checked`)?.value === truth, wrap = $('#' + wrapId), input = $('#' + inputId);
            if (wrap)
                wrap.hidden = !on;
            if (input) {
                input.disabled = !on;
                if (!on) {
                    input.value = '';
                }
            }
        };
        $$(`input[name="${name}"]`).forEach(x => x.addEventListener('change', sync));
        sync();
    };
    bind('quizTattoo', 'quizTattooDateWrap', 'quizTattooDate');
    bind('quizPiercing', 'quizPiercingDateWrap', 'quizPiercingDate');
    bind('quizAcupuncture', 'quizAcupunctureDateWrap', 'quizAcupunctureDate');
    bind('quizMedication', 'quizMedicationWrap', 'quizMedicationDetails');
    bind('quizAlcohol', 'quizAlcoholWrap', 'quizAlcoholTime');
    bind('quizNicotine', 'quizNicotineWrap', 'quizNicotineTime');
    bind('quizDonatedBefore', 'quizLastDonationWrap', 'quizLastDonationDate');
    const syncPostpartum = () => {
        const on = $('input[name="quizPregnancy"]:checked')?.value === 'recent_birth', wrap = $('#quizPostpartumWrap'), input = $('#quizPostpartumDate');
        if (wrap)
            wrap.hidden = !on;
        if (input) {
            input.disabled = !on;
            if (!on)
                input.value = '';
        }
    };
    $$('input[name="quizPregnancy"]').forEach(x => x.addEventListener('change', syncPostpartum));
    syncPostpartum();
}
function renderDonorQuiz() {
    const step = donorQuizSteps[donorQuizStep], q = $('#donorQuizQuestion'), a = $('#donorQuizAnswer'), label = $('#donorQuizStepLabel'), progress = $('#donorQuizProgress'), back = $('#donorQuizBack'), next = $('#donorQuizNext');
    if (!step || !q || !a)
        return;
    q.innerHTML = `<span class="quiz-question-number">QUESTION ${donorQuizStep + 1}</span><h3>${esc(step.title)}</h3><p>${esc(step.help)}</p>`;
    a.innerHTML = step.render();
    if (label)
        label.textContent = `Question ${donorQuizStep + 1} of ${donorQuizSteps.length}`;
    if (progress)
        progress.style.width = `${((donorQuizStep + 1) / donorQuizSteps.length) * 100}%`;
    if (back)
        back.disabled = donorQuizStep === 0;
    if (next)
        next.textContent = donorQuizStep === donorQuizSteps.length - 1 ? 'Check My Eligibility' : 'Next';
    donorQuizError();
    bindDonorQuizFollowups();
}
const checkedValues = name => $$(`input[name="${name}"]:checked`).map(x => x.value);
function readDonorQuizStep() {
    donorQuizError();
    if (donorQuizStep === 0) {
        const v = $('#quizBirthDate')?.value || '', age = donorAge(v);
        if (!v)
            return donorQuizError('Please enter your birth date.'), false;
        if (v >= today())
            return donorQuizError('Birth date must be in the past.'), false;
        donorQuizAnswers.birth_date = v;
        if (age === null)
            return donorQuizError('Please enter a valid birth date.'), false;
    }
    if (donorQuizStep === 1) {
        const v = Number($('#quizWeight')?.value || 0);
        if (!v)
            return donorQuizError('Please enter your current weight.'), false;
        donorQuizAnswers.weight_kg = String(v);
    }
    if (donorQuizStep === 2) {
        donorQuizAnswers.current_illness = $('input[name="quizIllness"]:checked')?.value === 'true';
        donorQuizAnswers.on_antibiotics = $('input[name="quizAntibiotics"]:checked')?.value === 'true';
    }
    if (donorQuizStep === 3) {
        donorQuizAnswers.permanent_conditions = checkedValues('quizPermanent');
        donorQuizAnswers.review_conditions = checkedValues('quizReview');
    }
    if (donorQuizStep === 4) {
        const on = $('input[name="quizMedication"]:checked')?.value === 'true', details = String($('#quizMedicationDetails')?.value || '').trim();
        if (on && !details)
            return donorQuizError('Please enter the medication name(s) for staff review.'), false;
        donorQuizAnswers.medication_current = on;
        donorQuizAnswers.medication_details = on ? details : '';
    }
    if (donorQuizStep === 5) {
        const v = $('input[name="quizTattoo"]:checked')?.value || 'false', date = $('#quizTattooDate')?.value || '';
        if (v === 'true' && !date)
            return donorQuizError('Please enter the date of your most recent tattoo.'), false;
        if (date && date > today())
            return donorQuizError('Tattoo date cannot be in the future.'), false;
        donorQuizAnswers.has_tattoo = v;
        donorQuizAnswers.tattoo_date = v === 'true' ? date : '';
    }
    if (donorQuizStep === 6) {
        const v = $('input[name="quizPiercing"]:checked')?.value || 'false', date = $('#quizPiercingDate')?.value || '';
        if (v === 'true' && !date)
            return donorQuizError('Please enter the date of your most recent piercing.'), false;
        if (date && date > today())
            return donorQuizError('Piercing date cannot be in the future.'), false;
        donorQuizAnswers.has_piercing = v;
        donorQuizAnswers.piercing_date = v === 'true' ? date : '';
    }
    if (donorQuizStep === 7) {
        const v = $('input[name="quizAcupuncture"]:checked')?.value || 'false', date = $('#quizAcupunctureDate')?.value || '';
        if (v === 'true' && !date)
            return donorQuizError('Please enter the date of your most recent acupuncture.'), false;
        if (date && date > today())
            return donorQuizError('Acupuncture date cannot be in the future.'), false;
        donorQuizAnswers.has_acupuncture = v;
        donorQuizAnswers.acupuncture_date = v === 'true' ? date : '';
    }
    if (donorQuizStep === 8) {
        const st = $('input[name="quizPregnancy"]:checked')?.value || 'not_applicable', date = $('#quizPostpartumDate')?.value || '';
        if (st === 'recent_birth' && !date)
            return donorQuizError('Please enter the delivery date.'), false;
        if (date && date > today())
            return donorQuizError('Delivery date cannot be in the future.'), false;
        donorQuizAnswers.pregnancy_status = st;
        donorQuizAnswers.postpartum_date = st === 'recent_birth' ? date : '';
        donorQuizAnswers.breastfeeding = !!$('#quizBreastfeeding')?.checked;
    }
    if (donorQuizStep === 9) {
        const on = $('input[name="quizAlcohol"]:checked')?.value === 'true', raw = $('#quizAlcoholTime')?.value || '';
        if (on && !raw)
            return donorQuizError('Please enter when you last consumed alcohol.'), false;
        const d = raw ? new Date(raw) : null;
        if (d && d > new Date())
            return donorQuizError('Alcohol time cannot be in the future.'), false;
        donorQuizAnswers.alcohol_last_24h = on;
        donorQuizAnswers.last_alcohol_at = on && d ? d.toISOString() : '';
    }
    if (donorQuizStep === 10) {
        const on = $('input[name="quizNicotine"]:checked')?.value === 'true', raw = $('#quizNicotineTime')?.value || '';
        if (on && !raw)
            return donorQuizError('Please enter when you last smoked or vaped.'), false;
        const d = raw ? new Date(raw) : null;
        if (d && d > new Date())
            return donorQuizError('Nicotine-use time cannot be in the future.'), false;
        donorQuizAnswers.smokes = on;
        donorQuizAnswers.last_nicotine_at = on && d ? d.toISOString() : '';
        donorQuizAnswers.other_habits = String($('#quizOtherHabits')?.value || '').trim();
    }
    if (donorQuizStep === 11) {
        const on = $('input[name="quizDonatedBefore"]:checked')?.value === 'true', date = $('#quizLastDonationDate')?.value || '';
        if (on && !date)
            return donorQuizError('Please enter your most recent donation date.'), false;
        if (date && date > today())
            return donorQuizError('Last donation date cannot be in the future.'), false;
        donorQuizAnswers.donated_before = on;
        donorQuizAnswers.last_donation_date = on ? date : '';
    }
    return true;
}
function buildDonorHealthSummary() {
    const parts = [];
    if (donorQuizAnswers.current_illness)
        parts.push('Current illness');
    if (donorQuizAnswers.on_antibiotics)
        parts.push('On antibiotics');
    parts.push(...donorQuizAnswers.permanent_conditions.map(x => donorPermanentLabels[x] || x));
    parts.push(...donorQuizAnswers.review_conditions.map(x => donorReviewLabels[x] || x));
    if (donorQuizAnswers.medication_current)
        parts.push('Medication: ' + donorQuizAnswers.medication_details);
    if (donorQuizAnswers.pregnancy_status === 'pregnant')
        parts.push('Currently pregnant');
    if (donorQuizAnswers.pregnancy_status === 'recent_birth')
        parts.push('Recent childbirth');
    if (donorQuizAnswers.breastfeeding)
        parts.push('Breastfeeding');
    return parts.join('; ') || 'None reported';
}
function evaluateDonorScreening() {
    const reasons = [], review = [], age = donorAge(donorQuizAnswers.birth_date), weight = Number(donorQuizAnswers.weight_kg || 0), now = new Date();
    let next = null, indefinite = false;
    if (age === null || age < 18 || age > 65)
        reasons.push('Age is outside BloodCare’s 18–65 online screening range.');
    if (weight < 50)
        reasons.push('Weight is below the 50 kg online screening minimum.');
    if (donorQuizAnswers.permanent_conditions.length) {
        reasons.push('Reported history requiring BloodCare staff guidance: ' + donorQuizAnswers.permanent_conditions.map(x => donorPermanentLabels[x] || x).join(', ') + '.');
        return {
            outcome: 'not_eligible', reasons, nextEligibleAt: null
        };
    }
    if (reasons.length)
        return {
            outcome: 'not_eligible', reasons, nextEligibleAt: null
        };
    if (donorQuizAnswers.current_illness) {
        reasons.push('Active illness or infection: wait until fully recovered.');
        indefinite = true;
    }
    if (donorQuizAnswers.on_antibiotics) {
        reasons.push('Antibiotic treatment for an infection: wait until treatment is completed and you are fully recovered.');
        indefinite = true;
    }
    [['has_tattoo', 'tattoo_date', 'Tattoo'], ['has_piercing', 'piercing_date', 'Piercing'], ['has_acupuncture', 'acupuncture_date', 'Acupuncture']].forEach(([flag, key, label]) => {
        if (donorQuizAnswers[flag] === 'true' && donorQuizAnswers[key]) {
            const ready = addBodyModWait(donorQuizAnswers[key]);
            if (ready && ready > now) {
                reasons.push(`${label}: conservative ${donorPolicy.body_mod_wait_months || 12}-month waiting period ends ${fmt(ready.toISOString())}.`);
                next = maxDate(next, ready);
            }
        }
    });
    if (donorQuizAnswers.pregnancy_status === 'pregnant') {
        reasons.push('Pregnancy requires temporary deferral and staff clearance after pregnancy.');
        indefinite = true;
    }
    if (donorQuizAnswers.pregnancy_status === 'recent_birth') {
        reasons.push('Recent childbirth requires postpartum recovery and staff review before donation.');
        indefinite = true;
    }
    if (donorQuizAnswers.alcohol_last_24h && donorQuizAnswers.last_alcohol_at) {
        const ready = new Date(new Date(donorQuizAnswers.last_alcohol_at).getTime() + (donorPolicy.alcohol_wait_hours || 24) * 3600000);
        if (ready > now) {
            reasons.push(`Alcohol: wait until at least ${ready.toLocaleString()} before donation.`);
            next = maxDate(next, ready);
        }
    }
    if (donorQuizAnswers.smokes && donorQuizAnswers.last_nicotine_at) {
        const ready = new Date(new Date(donorQuizAnswers.last_nicotine_at).getTime() + (donorPolicy.nicotine_wait_hours || 4) * 3600000);
        if (ready > now) {
            reasons.push(`Smoking/vaping: wait until at least ${ready.toLocaleString()} before donation.`);
            next = maxDate(next, ready);
        }
    }
    if (donorQuizAnswers.donated_before && donorQuizAnswers.last_donation_date) {
        const d = new Date(donorQuizAnswers.last_donation_date + 'T00:00:00');
        d.setDate(d.getDate() + Number(donorPolicy.donation_interval_days || 90));
        if (d > now) {
            reasons.push(`Previous donation: the current ${donorPolicy.donation_interval_days || 90}-day interval ends ${fmt(d.toISOString())}.`);
            next = maxDate(next, d);
        }
    }
    if (donorQuizAnswers.review_conditions.length)
        review.push('Medical history requires staff / medical review: ' + donorQuizAnswers.review_conditions.map(x => donorReviewLabels[x] || x).join(', ') + '.');
    if (donorQuizAnswers.medication_current)
        review.push('Current medication requires staff review before donation.');
    if (donorQuizAnswers.breastfeeding)
        review.push('Breastfeeding requires individual staff review.');
    if (reasons.length)
        return {
            outcome: 'temporarily_deferred', reasons: [...reasons, ...review], nextEligibleAt: indefinite ? null : (next ? next.toISOString() : null)
        };
    if (review.length)
        return {
            outcome: 'needs_review', reasons: review, nextEligibleAt: null
        };
    return {
        outcome: 'preliminarily_eligible', reasons: ['No automatic deferral was identified by the online pre-screen. Final eligibility still requires staff screening, vital signs, hemoglobin assessment, and blood-service review.'], nextEligibleAt: null
    };
}
function syncDonorQuizToForm(evaluation) {
    donorQuizOutcome = evaluation.outcome;
    const map = {
        donorBirthDate: donorQuizAnswers.birth_date, donorWeight: donorQuizAnswers.weight_kg, donorHealthIssues: buildDonorHealthSummary(), hasTattoo: donorQuizAnswers.has_tattoo, tattooDate: donorQuizAnswers.tattoo_date, hasPiercing: donorQuizAnswers.has_piercing, piercingDate: donorQuizAnswers.piercing_date, drinksAlcohol: String(!!donorQuizAnswers.alcohol_last_24h), smokes: String(!!donorQuizAnswers.smokes), otherHabits: donorQuizAnswers.other_habits, donorLastDonation: donorQuizAnswers.last_donation_date
    };
    Object.entries(map).forEach(([id, v]) => {
        const el = $('#' + id);
        if (el)
            el.value = v;
    });
    const summary = $('#screeningSummary'), age = donorAge(donorQuizAnswers.birth_date), label = evaluation.outcome === 'preliminarily_eligible' ? 'Preliminarily Eligible' : evaluation.outcome === 'temporarily_deferred' ? 'Temporarily Deferred' : evaluation.outcome === 'needs_review' ? 'Needs Staff Review' : 'Not Eligible Online';
    if (summary)
        summary.innerHTML = `<b>Pre-screen: ${esc(label)}</b><div><span>Age <strong>${age}</strong></span><span>Weight <strong>${esc(donorQuizAnswers.weight_kg)} kg</strong></span><span>Tattoo <strong>${donorQuizAnswers.has_tattoo === 'true' ? 'Yes' : 'No'}</strong></span><span>Piercing <strong>${donorQuizAnswers.has_piercing === 'true' ? 'Yes' : 'No'}</strong></span><span>Acupuncture <strong>${donorQuizAnswers.has_acupuncture === 'true' ? 'Yes' : 'No'}</strong></span></div><small>${esc(evaluation.reasons.join(' '))}</small>`;
}
function finishDonorQuiz() {
    const evaluation = evaluateDonorScreening(), result = $('#donorQuizResult'), quiz = $('#donorEligibilityQuiz'), registration = $('#donorRegistrationSection'), form = $('#donorForm');
    if (!result)
        return;
    if (registration)
        registration.hidden = true;
    if (form) {
        form.dataset.qualified = '0';
        form.dataset.screeningOutcome = evaluation.outcome;
    }
    quiz.hidden = true;
    result.hidden = false;
    donorQuizOutcome = evaluation.outcome;
    const reasonsHtml = `<ul class="quiz-result-reasons">${evaluation.reasons.map(x => `<li>${esc(x)}</li>`).join('')}</ul>`;
    const restart = `<button id="restartDonorQuiz" class="secondary-btn" type="button">Review My Answers</button>`;
    const bindRestart = () => $('#restartDonorQuiz')?.addEventListener('click', () => {
        result.hidden = true;
        if (registration)
            registration.hidden = true;
        if (form)
            form.dataset.qualified = '0';
        quiz.hidden = false;
        donorQuizStep = 0;
        renderDonorQuiz();
        quiz.scrollIntoView({
            behavior: 'smooth', block: 'start'
        });
    });
    if (evaluation.outcome === 'not_eligible') {
        result.className = 'glass-card donor-quiz-result not-qualified';
        result.innerHTML = `<div class="quiz-result-icon">!</div><span class="section-label">ONLINE PRE-SCREEN RESULT</span><h2>BloodCare cannot clear this registration online.</h2><p>This does not replace an official blood-center assessment. Please contact BloodCare staff if you need clarification.</p>${reasonsHtml}${restart}`;
        bindRestart();
        return;
    }
    syncDonorQuizToForm(evaluation);
    const f = $('#donorForm');
    if (f) {
        f.dataset.qualified = '1';
        f.dataset.screeningOutcome = evaluation.outcome;
    }
    if (evaluation.outcome === 'temporarily_deferred') {
        result.className = 'glass-card donor-quiz-result deferred';
        result.innerHTML = `<div class="quiz-result-icon">⌛</div><span class="section-label">TEMPORARILY DEFERRED</span><h2>You may be able to donate later.</h2><p>Your donor profile can still be saved now so staff can review it and confirm when you may donate.</p>${reasonsHtml}<div class="quiz-nav-actions"><button id="unlockDonorRegistration" class="primary-btn" type="button">Save Donor Profile</button>${restart}</div>`;
    }
    else if (evaluation.outcome === 'needs_review') {
        result.className = 'glass-card donor-quiz-result needs-review';
        result.innerHTML = `<div class="quiz-result-icon">?</div><span class="section-label">STAFF REVIEW REQUIRED</span><h2>Your answers need individual review.</h2><p>No automatic rejection was made. Complete your donor profile and BloodCare staff will make the final decision.</p>${reasonsHtml}<div class="quiz-nav-actions"><button id="unlockDonorRegistration" class="primary-btn" type="button">Continue Registration</button>${restart}</div>`;
    }
    else {
        result.className = 'glass-card donor-quiz-result qualified';
        result.innerHTML = `<div class="quiz-result-icon">✓</div><span class="section-label">PRELIMINARILY ELIGIBLE</span><h2>You passed the online pre-screen.</h2><p>Complete your donor profile. Final eligibility still requires staff screening, vital signs, hemoglobin assessment, and blood-service review.</p>${reasonsHtml}<div class="quiz-nav-actions"><button id="unlockDonorRegistration" class="primary-btn" type="button">Register as Donor</button>${restart}</div>`;
    }
    $('#unlockDonorRegistration')?.addEventListener('click', () => {
        registration.hidden = false;
        registration.scrollIntoView({
            behavior: 'smooth', block: 'start'
        });
    });
    bindRestart();
}
function evaluateDonorEligibility(show = true) {
    const f = $('#donorForm'), ok = !!f && f.dataset.qualified === '1' && f.dataset.screeningOutcome !== 'not_eligible';
    if (!ok && show)
        toast('Complete the donor eligibility pre-screen first.', 'err');
    return ok;
}
export { donorAge, donorReviewLabels };
export function init() {
    $('#donorQuizNext')?.addEventListener('click', () => {
        if (!readDonorQuizStep())
            return;
        if (donorQuizStep < donorQuizSteps.length - 1) {
            donorQuizStep++;
            renderDonorQuiz();
        }
        else
            finishDonorQuiz();
    });
    $('#donorQuizBack')?.addEventListener('click', () => {
        if (donorQuizStep > 0) {
            readDonorQuizStep();
            donorQuizStep--;
            renderDonorQuiz();
        }
    });
    if ($('#donorEligibilityQuiz')) {
        loadDonorScreeningPolicy().finally(renderDonorQuiz);
    }
    $('#donorForm')?.addEventListener('submit', async (e) => {
        e.preventDefault();
        if (!sb)
            return toast('BloodCare API is unavailable.', 'err');
        if (!evaluateDonorEligibility(true))
            return;
        const btn = e.submitter;
        const data = Object.fromEntries(new FormData(e.target));
        data.email = String(data.email || '').trim().toLowerCase();
        data.phone = normalizePhone(data.phone);
        data.has_tattoo = String(data.has_tattoo) === 'true';
        data.has_piercing = String(data.has_piercing) === 'true';
        data.drinks_alcohol = String(data.drinks_alcohol) === 'true';
        data.smokes = String(data.smokes) === 'true';
        data.screening_answers = {
            ...donorQuizAnswers
        };
        if (data.birth_date >= today())
            return toast('Birth date must be in the past.', 'err');
        if (data.last_donation_date && data.last_donation_date > today())
            return toast('Last donation date cannot be in the future.', 'err');
        loading(btn, true);
        const { data: code, error } = await sb.rpc('register_donor', {
            p_data: data
        });
        if (error) {
            loading(btn, false);
            return toast(error.message, 'err');
        }
        const preferredFacility = query.get('facility_id');
        if (preferredFacility) {
            const linked = await sb.rpc('set_my_donor_facility', {
                p_facility_id: preferredFacility
            });
            if (linked.error)
                toast('Donor profile was saved, but the selected facility could not be linked: ' + linked.error.message, 'err');
        }
        loading(btn, false);
        showReceipt($('#donorReceipt'), 'Registration received', code, 'Your detailed online pre-screen and donor profile were submitted. Staff will review your information and confirm final eligibility.');
        profileState.payload = null;
        const receipt = $('#donorReceipt');
        if (receipt) {
            receipt.insertAdjacentHTML('beforeend', '<a href="profile.html" class="secondary-btn" style="margin-left:8px">Open My Profile</a>');
            if (preferredFacility)
                receipt.insertAdjacentHTML('beforeend', `<a href="appointment.html?facility_id=${encodeURIComponent(preferredFacility)}" class="secondary-btn" style="margin-left:8px">Book at Selected Facility</a>`);
        }
    });
}
