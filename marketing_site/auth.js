(() => {
  const SUPABASE_URL = 'https://doncoxjilytojmnpukxi.supabase.co';
  const SUPABASE_KEY = 'sb_publishable_ou8SpZL5IQKN1wBlMEIcUg_QlLWEx5X';
  const TURNSTILE_KEY = '0x4AAAAAAEBHmcYfqXksAdir';
  const isSignup = window.location.pathname.replace(/\/$/, '').endsWith('/signup');
  const form = document.getElementById('auth-form');
  const email = document.getElementById('email');
  const password = document.getElementById('password');
  const confirm = document.getElementById('confirm');
  const confirmWrap = document.getElementById('confirm-wrap');
  const recoveryWrap = document.getElementById('recovery-wrap');
  const submit = document.getElementById('submit');
  const status = document.getElementById('status');
  let widgetId = null;

  const showStatus = (message, kind = '') => {
    status.textContent = message;
    status.className = `status show ${kind}`;
  };
  const resetCaptcha = () => {
    if (widgetId !== null && window.turnstile) window.turnstile.reset(widgetId);
  };
  const captchaToken = () => widgetId === null ? null : window.turnstile.getResponse(widgetId);

  if (isSignup) {
    document.title = 'Create Account | PI Prop Intelligence';
    document.getElementById('mode-label').textContent = 'NEW PI MEMBERSHIP';
    document.getElementById('auth-title').textContent = 'Create your account';
    document.getElementById('auth-subtitle').textContent = 'Set up secure access to your PI workspace.';
    document.getElementById('switch-copy').innerHTML = 'Already a member? <a href="/login">Sign in</a>';
    confirmWrap.hidden = false;
    confirm.required = true;
    password.autocomplete = 'new-password';
    recoveryWrap.hidden = true;
    submit.textContent = 'CREATE ACCOUNT';
  }

  window.addEventListener('load', async () => {
    const client = window.supabase.createClient(SUPABASE_URL, SUPABASE_KEY, {
      auth: {persistSession: true, autoRefreshToken: true, detectSessionInUrl: true}
    });
    const {data: {session}} = await client.auth.getSession();
    if (session) {
      window.location.replace('/workspace');
      return;
    }
    if (window.turnstile) {
      widgetId = window.turnstile.render('#turnstile', {
        sitekey: TURNSTILE_KEY,
        theme: 'dark',
        size: 'flexible',
      });
    }

    form.addEventListener('submit', async (event) => {
      event.preventDefault();
      if (isSignup && password.value !== confirm.value) {
        showStatus('Passwords do not match.', 'error');
        return;
      }
      const token = captchaToken();
      if (!token) {
        showStatus('Complete the security check, then try again.', 'error');
        return;
      }
      submit.disabled = true;
      showStatus(isSignup ? 'Creating your account...' : 'Signing you in...');
      const credentials = {email: email.value.trim(), password: password.value};
      const result = isSignup
        ? await client.auth.signUp({...credentials, options: {emailRedirectTo: `${window.location.origin}/auth/callback`, captchaToken: token}})
        : await client.auth.signInWithPassword({...credentials, options: {captchaToken: token}});
      submit.disabled = false;
      if (result.error) {
        showStatus(result.error.message, 'error');
        resetCaptcha();
        return;
      }
      if (result.data.session) {
        window.location.replace('/workspace');
      } else {
        showStatus('Check your email to confirm your account, then sign in.', 'ok');
        resetCaptcha();
      }
    });

    document.getElementById('recovery').addEventListener('click', async () => {
      if (!email.value.trim()) {
        showStatus('Enter your email address first.', 'error');
        return;
      }
      const token = captchaToken();
      if (!token) {
        showStatus('Complete the security check, then try again.', 'error');
        return;
      }
      const {error} = await client.auth.resetPasswordForEmail(email.value.trim(), {
        redirectTo: `${window.location.origin}/auth/callback?auth_action=recovery`,
        captchaToken: token,
      });
      showStatus(error ? error.message : 'Password reset email sent.', error ? 'error' : 'ok');
      resetCaptcha();
    });
  });
})();
