/* BizKipe anonymous visit counter. Stores a random ID in this browser only: no name, email or IP. */
(function () {
  try {
    if (navigator.doNotTrack === '1' || window.doNotTrack === '1') return;
    var vid = null;
    try {
      vid = localStorage.getItem('bizkipe_vid');
      if (!vid || !/^[A-Za-z0-9-]{16,64}$/.test(vid)) {
        vid = (window.crypto && crypto.randomUUID) ? crypto.randomUUID() : (Date.now().toString(36) + Math.random().toString(36).slice(2) + Math.random().toString(36).slice(2));
        vid = vid.replace(/[^A-Za-z0-9-]/g, '').slice(0, 64);
        if (vid.length < 16) vid = vid + '0000000000000000';
        localStorage.setItem('bizkipe_vid', vid);
      }
    } catch (e) { return; }
    function inApp() {
      try { return window.matchMedia('(display-mode: standalone)').matches || window.navigator.standalone === true; } catch (e) { return false; }
    }
    function signedIn() {
      try { for (var i = 0; i < localStorage.length; i++) { var k = localStorage.key(i); if (k && /^sb-.*-auth-token$/.test(k)) return true; } } catch (e) {}
      return false;
    }
    function send(extra) {
      var body = { vid: vid, page: location.pathname };
      if (inApp()) body.app = true;
      if (signedIn()) body.signedIn = true;
      if (extra && extra.installed) body.installed = true;
      try {
        fetch('/api/ping', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body), keepalive: true }).catch(function () {});
      } catch (e) {}
    }
    function tick() { if (document.visibilityState === 'visible') send(); }
    tick();
    setInterval(tick, 60000);
    document.addEventListener('visibilitychange', tick);
    window.addEventListener('appinstalled', function () { send({ installed: true }); });
  } catch (e) {}
})();
