/* BizKipe install prompt: friendly bottom banner + footer link (#installApp) as backup.
   Chrome/Edge/Samsung on Android fire beforeinstallprompt; iOS gets a how-to tip. */
(function () {
  'use strict';
  var KEY = 'bizkipe_install_dismissed', DAYS = 14;
  var dp = null, banner = null, timer = null;
  var link = document.getElementById('installApp');
  var delay = typeof window.BIZKIPE_INSTALL_DELAY === 'number' ? window.BIZKIPE_INSTALL_DELAY : 8000;

  function standalone() {
    try {
      return (window.matchMedia && window.matchMedia('(display-mode: standalone)').matches) || window.navigator.standalone === true;
    } catch (e) { return false; }
  }
  function isIOS() {
    var ua = navigator.userAgent || '';
    return /iPad|iPhone|iPod/.test(ua) || (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1);
  }
  function dismissed() {
    try {
      var t = parseInt(localStorage.getItem(KEY), 10);
      return t && (Date.now() - t) < DAYS * 864e5;
    } catch (e) { return false; }
  }
  function remember() { try { localStorage.setItem(KEY, String(Date.now())); } catch (e) {} }
  function hideBanner() { if (banner && banner.parentNode) banner.parentNode.removeChild(banner); banner = null; }
  function typing() {
    var a = document.activeElement;
    return a && /^(INPUT|TEXTAREA|SELECT)$/.test(a.tagName);
  }

  function build(ios) {
    if (banner || standalone()) return;
    banner = document.createElement('div');
    banner.id = 'installBanner';
    banner.setAttribute('role', 'dialog');
    banner.setAttribute('aria-label', 'Install BizKipe');
    banner.style.cssText = 'position:fixed;left:0;right:0;bottom:0;z-index:9999;display:flex;justify-content:center;padding:12px 12px calc(12px + env(safe-area-inset-bottom));pointer-events:none';
    var card = document.createElement('div');
    card.style.cssText = 'pointer-events:auto;box-sizing:border-box;width:100%;max-width:440px;background:#fff;color:#241b3d;border:1px solid #e2dcf3;border-radius:16px;box-shadow:0 8px 30px rgba(36,27,61,.25);padding:14px;display:flex;gap:12px;align-items:center;font-family:inherit';
    var img = document.createElement('img');
    img.src = '/icon-192.png'; img.alt = ''; img.width = 44; img.height = 44;
    img.style.cssText = 'border-radius:10px;flex:none';
    var txt = document.createElement('div');
    txt.style.cssText = 'flex:1;min-width:0;font-size:14px;line-height:1.35';
    var h = document.createElement('div');
    h.style.cssText = 'font-weight:800;font-size:15px';
    h.textContent = 'Install BizKipe';
    var p = document.createElement('div');
    p.style.cssText = 'color:#5b5275';
    p.textContent = ios ? 'Tap Share, then Add to Home Screen.' : 'Use it like an app, right from your home screen.';
    txt.appendChild(h); txt.appendChild(p);
    var btns = document.createElement('div');
    btns.style.cssText = 'display:flex;flex-direction:column;gap:6px;flex:none';
    var no = document.createElement('button');
    no.type = 'button'; no.textContent = ios ? 'Got it' : 'Not now';
    no.style.cssText = 'background:none;border:0;color:#5b5275;font:inherit;font-size:13px;cursor:pointer;padding:4px 8px';
    no.addEventListener('click', function () { remember(); hideBanner(); });
    if (!ios) {
      var yes = document.createElement('button');
      yes.type = 'button'; yes.textContent = 'Install';
      yes.style.cssText = 'background:#6a3df0;color:#fff;border:0;border-radius:10px;font:inherit;font-weight:700;font-size:14px;padding:9px 16px;cursor:pointer';
      yes.addEventListener('click', doInstall);
      btns.appendChild(yes);
    }
    btns.appendChild(no);
    card.appendChild(img); card.appendChild(txt); card.appendChild(btns);
    banner.appendChild(card);
    document.body.appendChild(banner);
  }

  function doInstall() {
    if (!dp) return;
    var e = dp; dp = null;
    hideBanner();
    try {
      e.prompt();
      e.userChoice.then(function (c) {
        if (c && c.outcome === 'accepted') { if (link) link.hidden = true; }
        else { remember(); dp = e; }
      }).catch(function () {});
    } catch (err) {}
  }

  function schedule(ios) {
    if (timer || dismissed() || standalone()) return;
    (function tick() {
      timer = setTimeout(function () {
        timer = null;
        if (typing()) return tick();
        if (!dp && !ios) return;
        build(ios);
      }, delay);
    })();
  }

  window.addEventListener('beforeinstallprompt', function (e) {
    e.preventDefault();
    dp = e;
    if (link && !standalone()) link.hidden = false;
    schedule(false);
  });
  window.addEventListener('appinstalled', function () {
    dp = null; hideBanner();
    if (link) link.hidden = true;
  });

  if (link) {
    link.addEventListener('click', function (ev) {
      ev.preventDefault();
      if (dp) { doInstall(); }
      else if (isIOS()) { hideBanner(); build(true); }
    });
    if (isIOS() && !standalone()) link.hidden = false;
  }
  if (isIOS() && !standalone()) schedule(true);
})();
