(() => {
  const SUPABASE_URL = 'https://doncoxjilytojmnpukxi.supabase.co';
  const SUPABASE_KEY = 'sb_publishable_ou8SpZL5IQKN1wBlMEIcUg_QlLWEx5X';
  const TURNSTILE_KEY = '0x4AAAAAAEBHmcYfqXksAdir';
  let client;
  let mode = 'login';
  let widgetId = null;

  const byId = (id) => document.getElementById(id);
  const dialog = byId('auth-dialog');
  const form = byId('modal-auth-form');
  const email = byId('modal-email');
  const password = byId('modal-password');
  const confirm = byId('modal-confirm');
  const confirmWrap = byId('modal-confirm-wrap');
  const recovery = byId('modal-recovery');
  const submit = byId('modal-submit');
  const status = byId('modal-status');

  const showStatus = (message, kind = '') => {
    status.textContent = message;
    status.className = `auth-status show ${kind}`;
  };
  const clearStatus = () => {
    status.textContent = '';
    status.className = 'auth-status';
  };
  const captchaToken = () => widgetId === null ? null : window.turnstile.getResponse(widgetId);
  const resetCaptcha = () => {
    if (widgetId !== null && window.turnstile) window.turnstile.reset(widgetId);
  };
  const ensureCaptcha = () => {
    if (widgetId === null && window.turnstile) {
      widgetId = window.turnstile.render('#auth-turnstile', {
        sitekey: TURNSTILE_KEY,
        theme: 'dark',
        size: 'flexible',
      });
    }
  };

  const setMode = (nextMode, updateHistory = true) => {
    mode = nextMode;
    const signup = mode === 'signup';
    byId('auth-mode').textContent = signup ? 'NEW PI MEMBERSHIP' : 'RETURNING MEMBER';
    byId('auth-heading').textContent = signup ? 'Create your account' : 'Welcome back';
    byId('auth-sub').textContent = signup
      ? 'Set up secure access to your PI workspace.'
      : 'Sign in to continue to your PI workspace.';
    confirmWrap.hidden = !signup;
    confirm.required = signup;
    recovery.hidden = signup;
    password.autocomplete = signup ? 'new-password' : 'current-password';
    submit.textContent = signup ? 'CREATE ACCOUNT' : 'SIGN IN';
    byId('modal-switch').innerHTML = signup
      ? 'Already a member? <button type="button" data-auth-mode="login">Sign in</button>'
      : 'New to PI? <button type="button" data-auth-mode="signup">Create your account</button>';
    clearStatus();
    if (updateHistory) history.pushState({auth: mode}, '', signup ? '/signup' : '/login');
  };

  const open = (nextMode, updateHistory = true) => {
    setMode(nextMode, updateHistory);
    if (!dialog.open) dialog.showModal();
    ensureCaptcha();
    window.setTimeout(() => email.focus(), 80);
  };
  const close = (updateHistory = true) => {
    if (dialog.open) dialog.close();
    clearStatus();
    if (updateHistory) history.pushState({}, '', '/');
  };

  window.addEventListener('load', async () => {
    client = window.supabase.createClient(SUPABASE_URL, SUPABASE_KEY, {
      auth: {persistSession: true, autoRefreshToken: true, detectSessionInUrl: true}
    });
    const {data: {session}} = await client.auth.getSession();
    if (session && ['/login', '/signup'].includes(window.location.pathname)) {
      window.location.replace('/workspace');
      return;
    }
    if (window.location.pathname === '/login') open('login', false);
    if (window.location.pathname === '/signup') open('signup', false);

    document.addEventListener('click', (event) => {
      const modeButton = event.target.closest('[data-auth-mode]');
      if (modeButton) {
        event.preventDefault();
        open(modeButton.dataset.authMode);
        return;
      }
      const link = event.target.closest('a[href]');
      if (!link) return;
      const url = new URL(link.href, window.location.origin);
      if (url.origin !== window.location.origin || !['/login', '/signup'].includes(url.pathname)) return;
      event.preventDefault();
      open(url.pathname === '/signup' ? 'signup' : 'login');
    });
    byId('auth-close').addEventListener('click', () => close());
    dialog.addEventListener('click', (event) => {
      if (event.target === dialog) close();
    });
    window.addEventListener('popstate', () => {
      if (window.location.pathname === '/login') open('login', false);
      else if (window.location.pathname === '/signup') open('signup', false);
      else close(false);
    });

    form.addEventListener('submit', async (event) => {
      event.preventDefault();
      if (mode === 'signup' && password.value !== confirm.value) {
        showStatus('Passwords do not match.', 'error');
        return;
      }
      const token = captchaToken();
      if (!token) {
        showStatus('Complete the security check, then try again.', 'error');
        return;
      }
      submit.disabled = true;
      showStatus(mode === 'signup' ? 'Creating your account...' : 'Signing you in...');
      const credentials = {email: email.value.trim(), password: password.value};
      const result = mode === 'signup'
        ? await client.auth.signUp({...credentials, options: {emailRedirectTo: `${window.location.origin}/auth/callback`, captchaToken: token}})
        : await client.auth.signInWithPassword({...credentials, options: {captchaToken: token}});
      submit.disabled = false;
      if (result.error) {
        const invalidCredentials = /invalid login credentials/i.test(result.error.message);
        showStatus(
          invalidCredentials
            ? 'Email or password not recognized. If you created this account with Google, use CONTINUE WITH GOOGLE or select Set / reset password.'
            : result.error.message,
          'error',
        );
        resetCaptcha();
      } else if (result.data.session) {
        window.location.replace('/workspace');
      } else {
        showStatus('Check your email to confirm your account, then sign in.', 'ok');
        resetCaptcha();
      }
    });
    byId('google-auth').addEventListener('click', async () => {
      clearStatus();
      const {error} = await client.auth.signInWithOAuth({
        provider: 'google',
        options: {redirectTo: window.location.origin + '/workspace'},
      });
      if (error) showStatus(error.message, 'error');
    });
    recovery.addEventListener('click', async () => {
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
        redirectTo: `${window.location.origin}/workspace?auth_action=recovery`,
        captchaToken: token,
      });
      showStatus(
        error ? error.message : 'Password setup email sent. Open it on this device to choose your password.',
        error ? 'error' : 'ok',
      );
      resetCaptcha();
    });
  });
})();
