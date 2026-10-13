(() => {
  'use strict';
  const root = document.documentElement;
  const themeMeta = document.querySelector('meta[name="theme-color"]');
  const media = window.matchMedia?.('(prefers-color-scheme: dark)');

  function preferredTheme(){
    try { return localStorage.getItem('bloodcare-theme') || (media?.matches ? 'dark' : 'light'); }
    catch { return media?.matches ? 'dark' : 'light'; }
  }
  function setTheme(theme, persist=true){
    const next = theme === 'dark' ? 'dark' : 'light';
    root.dataset.theme = next;
    root.style.colorScheme = next;
    themeMeta?.setAttribute('content', next === 'dark' ? '#160f11' : '#b91c1c');
    document.querySelectorAll('.theme-toggle').forEach(btn => {
      btn.setAttribute('aria-label', next === 'dark' ? 'Switch to light mode' : 'Switch to dark mode');
      btn.setAttribute('title', next === 'dark' ? 'Light mode' : 'Dark mode');
    });
    if(persist){ try { localStorage.setItem('bloodcare-theme', next); } catch {} }
  }
  setTheme(root.dataset.theme || preferredTheme(), false);
  document.addEventListener('click', e => {
    const toggle = e.target.closest('.theme-toggle');
    if(toggle) setTheme(root.dataset.theme === 'dark' ? 'light' : 'dark');
  });

  // Mission / Vision / Goal interactive tabs.
  const mvgButtons = [...document.querySelectorAll('[data-mvg-tab]')];
  const mvgPanels = [...document.querySelectorAll('[data-mvg-panel]')];
  function activateMvg(name){
    mvgButtons.forEach(btn => {
      const active = btn.dataset.mvgTab === name;
      btn.classList.toggle('active', active);
      btn.setAttribute('aria-selected', active ? 'true' : 'false');
    });
    mvgPanels.forEach(panel => panel.classList.toggle('active', panel.dataset.mvgPanel === name));
  }
  mvgButtons.forEach(btn => btn.addEventListener('click', () => activateMvg(btn.dataset.mvgTab)));

  // Gentle slide/fade-in as sections enter the viewport.
  const revealTargets = [...document.querySelectorAll('main > section, .page-title, .glass-card, .panel')]
    .filter(el => !el.closest('.modal-backdrop'));
  if('IntersectionObserver' in window && !window.matchMedia('(prefers-reduced-motion: reduce)').matches){
    revealTargets.forEach((el, i) => {
      el.classList.add('reveal-on-scroll');
      el.style.setProperty('--reveal-delay', `${Math.min(i % 4, 3) * 55}ms`);
    });
    const observer = new IntersectionObserver(entries => {
      entries.forEach(entry => {
        if(entry.isIntersecting){ entry.target.classList.add('is-visible'); observer.unobserve(entry.target); }
      });
    }, {threshold: .08, rootMargin: '0px 0px -35px 0px'});
    revealTargets.forEach(el => observer.observe(el));
  } else revealTargets.forEach(el => el.classList.add('is-visible'));

  // Public contact modal. Visitors can send a message without signing in.
  const contactTriggers = [...document.querySelectorAll('[data-contact-open]')];
  if(contactTriggers.length){
    const modal = document.createElement('div');
    modal.className = 'modal-backdrop contact-modal-backdrop';
    modal.id = 'contactModal';
    modal.hidden = true;
    modal.innerHTML = `
      <section class="modal-card contact-modal-card" role="dialog" aria-modal="true" aria-labelledby="contactModalTitle">
        <button class="modal-close contact-modal-close" type="button" aria-label="Close contact form">×</button>
        <div class="contact-modal-heading">
          <span class="section-label">CONTACT BLOODCARE</span>
          <h2 id="contactModalTitle">How can we help?</h2>
          <p>You do not need an account to contact BloodCare. Fill in the form and our team can review your inquiry.</p>
        </div>
        <form id="contactForm" class="contact-form-grid" novalidate>
          <div class="form-group">
            <label for="contactFullName">Full Name</label>
            <input id="contactFullName" name="full_name" autocomplete="name" maxlength="120" required placeholder="Enter your full name">
          </div>
          <div class="form-group">
            <label for="contactEmail">Email Address</label>
            <input id="contactEmail" name="email" type="email" autocomplete="email" maxlength="254" required placeholder="you@example.com">
          </div>
          <div class="form-group">
            <label for="contactPhone">Contact No.</label>
            <input id="contactPhone" name="phone" type="tel" inputmode="numeric" autocomplete="tel" minlength="7" maxlength="15" pattern="[0-9]{7,15}" required placeholder="09123456789">
          </div>
          <div class="form-group">
            <label for="contactInquiryType">Inquiry Type</label>
            <select id="contactInquiryType" name="inquiry_type" required>
              <option value="general">General Inquiry</option>
              <option value="donation">Blood Donation</option>
              <option value="blood-request">Blood Request</option>
              <option value="appointment">Appointment</option>
              <option value="facility">Facility / Blood Availability</option>
              <option value="technical">Technical Support</option>
              <option value="other">Other</option>
            </select>
          </div>
          <div class="form-group full">
            <label for="contactMessage">Message</label>
            <textarea id="contactMessage" name="message" rows="5" minlength="10" maxlength="3000" required placeholder="Tell us how BloodCare can help you..."></textarea>
            <small class="contact-help">Please do not include passwords or other account credentials.</small>
          </div>
          <div class="contact-form-status full" id="contactFormStatus" role="status" aria-live="polite"></div>
          <div class="contact-form-actions full">
            <button class="secondary-btn contact-cancel" type="button">Cancel</button>
            <button class="primary-btn contact-submit" type="submit">Send Message</button>
          </div>
        </form>
      </section>`;
    document.body.appendChild(modal);

    const form = modal.querySelector('#contactForm');
    const status = modal.querySelector('#contactFormStatus');
    const submit = modal.querySelector('.contact-submit');
    const fullNameInput = modal.querySelector('#contactFullName');
    const emailInput = modal.querySelector('#contactEmail');
    const phoneInput = modal.querySelector('#contactPhone');
    const modalIntro = modal.querySelector('.contact-modal-heading p');
    const closeButtons = [modal.querySelector('.contact-modal-close'), modal.querySelector('.contact-cancel')];
    let returnFocus = null;

    // Contact numbers are digits only. This also sanitizes pasted values.
    phoneInput?.addEventListener('input', () => {
      phoneInput.value = phoneInput.value.replace(/\D/g, '').slice(0, 15);
    });

    async function populateContactIdentity(){
      if(!fullNameInput || !emailInput) return;
      const hadAccountIdentity = fullNameInput.dataset.accountPrefilled === '1' || emailInput.dataset.accountPrefilled === '1';
      fullNameInput.readOnly = false;
      emailInput.readOnly = false;
      fullNameInput.classList.remove('contact-account-field');
      emailInput.classList.remove('contact-account-field');
      delete fullNameInput.dataset.accountPrefilled;
      delete emailInput.dataset.accountPrefilled;
      if(hadAccountIdentity){ fullNameInput.value = ''; emailInput.value = ''; }
      if(modalIntro) modalIntro.textContent = 'You do not need an account to contact BloodCare. Fill in the form and our team can review your inquiry.';
      try{
        const response = await fetch('/api/auth/session', {credentials:'same-origin', cache:'no-store'});
        if(!response.ok) return;
        const data = await response.json().catch(() => ({}));
        const user = data?.user;
        if(!user) return;
        const accountName = String(user?.user_metadata?.full_name || user?.user_metadata?.name || '').trim();
        fullNameInput.value = accountName || String(user.email || '').split('@')[0] || '';
        emailInput.value = String(user.email || '').trim();
        fullNameInput.readOnly = true;
        emailInput.readOnly = true;
        fullNameInput.classList.add('contact-account-field');
        emailInput.classList.add('contact-account-field');
        fullNameInput.dataset.accountPrefilled = '1';
        emailInput.dataset.accountPrefilled = '1';
        if(modalIntro) modalIntro.textContent = 'Your BloodCare account name and email are filled automatically. Add your contact number and inquiry details below.';
      }catch{}
    }

    const closeContact = () => {
      modal.hidden = true;
      document.body.classList.remove('contact-modal-open');
      status.textContent = '';
      status.className = 'contact-form-status full';
      if(returnFocus && document.contains(returnFocus)) returnFocus.focus();
    };
    const openContact = async trigger => {
      returnFocus = trigger || document.activeElement;
      modal.hidden = false;
      document.body.classList.add('contact-modal-open');
      const nav = document.querySelector('.nav-links');
      nav?.classList.remove('open');
      document.querySelector('.menu-btn')?.setAttribute('aria-expanded','false');
      await populateContactIdentity();
      window.setTimeout(() => {
        const target = fullNameInput?.readOnly ? phoneInput : fullNameInput;
        target?.focus();
      }, 20);
    };

    contactTriggers.forEach(btn => btn.addEventListener('click', e => {
      e.preventDefault();
      const page = (location.pathname.split('/').pop() || 'index.html').toLowerCase();
      const isPublicHome = page === 'index.html' || location.pathname === '/';
      const isDesktopNavContact = isPublicHome && btn.classList.contains('nav-contact-link') && window.matchMedia('(min-width: 769px)').matches;
      const footer = document.querySelector('footer.site-footer#contact');
      if(isDesktopNavContact && footer){
        const nav = document.querySelector('.nav-links');
        nav?.classList.remove('open');
        document.querySelector('.menu-btn')?.setAttribute('aria-expanded','false');
        footer.scrollIntoView({behavior:'smooth', block:'start'});
        // Open after the smooth scroll completes. The timeout is a fallback for
        // browsers without the scrollend event. Mobile opens immediately.
        let opened = false;
        const finish = () => { if(opened) return; opened = true; openContact(btn); };
        window.addEventListener?.('scrollend', finish, {once:true});
        window.setTimeout(finish, 850);
        return;
      }
      openContact(btn);
    }));
    closeButtons.forEach(btn => btn?.addEventListener('click', closeContact));
    modal.addEventListener('click', e => { if(e.target === modal) closeContact(); });
    document.addEventListener('keydown', e => { if(e.key === 'Escape' && !modal.hidden) closeContact(); });

    form.addEventListener('submit', async e => {
      e.preventDefault();
      if(!form.reportValidity()) return;
      const values = Object.fromEntries(new FormData(form));
      const payload = {
        full_name: String(values.full_name || '').trim(),
        email: String(values.email || '').trim(),
        phone: String(values.phone || '').trim(),
        inquiry_type: String(values.inquiry_type || 'general'),
        message: String(values.message || '').trim(),
        source_page: location.pathname + location.search
      };
      submit.disabled = true;
      submit.textContent = 'Sending…';
      status.textContent = '';
      status.className = 'contact-form-status full';
      try {
        const response = await fetch('/api/contact', {
          method: 'POST',
          headers: {'Content-Type':'application/json'},
          credentials: 'same-origin',
          body: JSON.stringify(payload)
        });
        const data = await response.json().catch(() => ({}));
        if(!response.ok) throw new Error(data.detail || 'Unable to send your message right now.');
        form.reset();
        await populateContactIdentity();
        status.textContent = 'Message sent. Thank you for contacting BloodCare.';
        status.className = 'contact-form-status full success';
        submit.textContent = 'Sent';
        window.setTimeout(closeContact, 1500);
      } catch(err) {
        status.textContent = err?.message || 'Unable to send your message right now.';
        status.className = 'contact-form-status full error';
        submit.disabled = false;
        submit.textContent = 'Send Message';
        return;
      }
      window.setTimeout(() => { submit.disabled = false; submit.textContent = 'Send Message'; }, 1600);
    });
  }

})();
