// Shared between the Mac and iPhone turntables: user album covers (localStorage), cover tint, synthesized vinyl sound.
window.VinylShared = window.VinylShared || (() => {
  const KEY = 'vinyl-covers-v1';
  const load = () => { try { return JSON.parse(localStorage.getItem(KEY)) || {}; } catch (e) { return {}; } };
  let covers = load();
  const subs = new Set();
  const emit = () => subs.forEach(f => { try { f(); } catch (e) {} });
  const save = () => { try { localStorage.setItem(KEY, JSON.stringify(covers)); } catch (e) {} emit(); };
  window.addEventListener('storage', e => { if (e.key === KEY) { covers = load(); emit(); } });

  // Real artwork lookup via the public iTunes Search API, cached in localStorage.
  const AKEY = 'vinyl-art-v3';
  let remote = (() => { try { return JSON.parse(localStorage.getItem(AKEY)) || {}; } catch (e) { return {}; } })();
  const pending = {};
  const keyOf = (t) => t ? (t.title + '|' + t.artist).toLowerCase() : '';
  function lookup(t) {
    const k = keyOf(t); if (!k || remote[k] || pending[k]) return; pending[k] = 1;
    fetch('https://itunes.apple.com/search?media=music&entity=song&limit=25&term=' + encodeURIComponent(t.title + ' ' + t.artist))
      .then(r => r.json()).then(j => {
        const norm = (s) => (s || '').toLowerCase().replace(/\s*[\(\[].*?[\)\]]/g, '').replace(/\s+-\s+.*$/, '').trim();
        const bad = /remix|live|karaoke|instrumental|acoustic|sped up|slowed|cover|tribute|8-bit|lullaby/i;
        const want = norm(t.title), artist = t.artist.toLowerCase();
        const scored = (j.results || []).map(x => {
          let s = 0;
          if (norm(x.trackName) === want) s += 10; else return null;
          if (bad.test(x.trackName) || bad.test(x.collectionName)) return null;
          const an = (x.artistName || '').toLowerCase();
          if (an === artist) s += 6; else if (an.includes(artist)) s += 3; else return null;
          if (!/ - (single|ep)$/i.test(x.collectionName || '')) s += 4;
          if (/deluxe|remaster|anniversary|expanded/i.test(x.collectionName || '')) s -= 1;
          if (/greatest|hits|best of|collection|essentials|now that/i.test(x.collectionName || '')) s -= 3;
          return { x, s };
        }).filter(Boolean).sort((a, b) => b.s - a.s);
        const res = scored.length ? scored[0].x : null;
        if (!res || !res.artworkUrl100) return;
        const url = res.artworkUrl100.replace(/\/\d+x\d+bb\./, '/600x600bb.');
        remote[k] = { url, tint: null, album: res.collectionName };
        try { localStorage.setItem(AKEY, JSON.stringify(remote)); } catch (e) {}
        emit();
        const img = new Image(); img.crossOrigin = 'anonymous';
        img.onload = () => { try { remote[k].tint = analyse(img).tint; localStorage.setItem(AKEY, JSON.stringify(remote)); emit(); } catch (e) {} };
        img.src = url;
      }).catch(() => {}).finally(() => { delete pending[k]; });
  }
  const cover = (i, fallback, t) => {
    if (covers[i]) return 'center / cover no-repeat url("' + covers[i].url + '")';
    const r = remote[keyOf(t)]; if (r) return 'center / cover no-repeat url("' + r.url + '"), ' + fallback;
    lookup(t); return fallback;
  };
  const tint = (i, fallback, t) => (covers[i] && covers[i].tint) || ((remote[keyOf(t)] || {}).tint) || fallback;
  const hasCover = (i) => !!covers[i];

  function analyse(img) {
    const S = 300, c = document.createElement('canvas'); c.width = S; c.height = S;
    const x = c.getContext('2d'), m = Math.min(img.width, img.height);
    x.drawImage(img, (img.width - m) / 2, (img.height - m) / 2, m, m, 0, 0, S, S);
    const url = c.toDataURL('image/jpeg', 0.85);
    const d = x.getImageData(0, 0, S, S).data;
    let r = 0, g = 0, b = 0, w = 0;
    for (let p = 0; p < d.length; p += 16) {
      const R = d[p], G = d[p + 1], B = d[p + 2], mx = Math.max(R, G, B), mn = Math.min(R, G, B);
      const sat = mx ? (mx - mn) / mx : 0, lum = (mx + mn) / 510, wt = sat * sat * (1 - Math.abs(lum - 0.5)) + 0.02;
      r += R * wt; g += G * wt; b += B * wt; w += wt;
    }
    const hex = (v) => Math.round(v / w).toString(16).padStart(2, '0');
    return { url, tint: '#' + hex(r) + hex(g) + hex(b) };
  }
  function pickCover(i) {
    const inp = document.createElement('input'); inp.type = 'file'; inp.accept = 'image/*';
    inp.onchange = () => {
      const f = inp.files && inp.files[0]; if (!f) return;
      const rd = new FileReader();
      rd.onload = () => { const img = new Image(); img.onload = () => { covers[i] = analyse(img); save(); }; img.src = rd.result; };
      rd.readAsDataURL(f);
    };
    inp.click();
  }
  const clearCover = (i) => { delete covers[i]; save(); };
  const subscribe = (f) => { subs.add(f); return () => subs.delete(f); };

  let ctx = null, crk = null, crkGain = null, enabled = true;
  const ac = () => { if (!ctx) { const A = window.AudioContext || window.webkitAudioContext; if (!A) return null; ctx = new A(); } if (ctx.state === 'suspended') ctx.resume(); return ctx; };
  function needleDrop() {
    if (!enabled) return; const c = ac(); if (!c) return; const t = c.currentTime;
    const o = c.createOscillator(), g = c.createGain();
    o.frequency.setValueAtTime(90, t); o.frequency.exponentialRampToValueAtTime(38, t + 0.14);
    g.gain.setValueAtTime(0.0001, t); g.gain.exponentialRampToValueAtTime(0.22, t + 0.008); g.gain.exponentialRampToValueAtTime(0.0001, t + 0.18);
    o.connect(g).connect(c.destination); o.start(t); o.stop(t + 0.2);
    const n = c.createBufferSource(), buf = c.createBuffer(1, c.sampleRate * 0.08, c.sampleRate), ch = buf.getChannelData(0);
    for (let k = 0; k < ch.length; k++) ch[k] = (Math.random() * 2 - 1) * Math.pow(1 - k / ch.length, 3);
    const bp = c.createBiquadFilter(); bp.type = 'bandpass'; bp.frequency.value = 2400; bp.Q.value = 0.8;
    const ng = c.createGain(); ng.gain.value = 0.12; n.buffer = buf; n.connect(bp).connect(ng).connect(c.destination); n.start(t);
  }
  function crackle(on) {
    if (on && !enabled) return;
    const c = on ? ac() : ctx; if (!c) return;
    if (on && !crk) {
      const len = c.sampleRate * 3, buf = c.createBuffer(1, len, c.sampleRate), ch = buf.getChannelData(0);
      for (let k = 0; k < len; k++) ch[k] = (Math.random() < 0.00035 ? (Math.random() * 2 - 1) * 0.8 : 0) + (Math.random() * 2 - 1) * 0.003;
      crk = c.createBufferSource(); crk.buffer = buf; crk.loop = true;
      const hp = c.createBiquadFilter(); hp.type = 'highpass'; hp.frequency.value = 900;
      crkGain = c.createGain(); crkGain.gain.setValueAtTime(0.0001, c.currentTime); crkGain.gain.exponentialRampToValueAtTime(0.14, c.currentTime + 0.6);
      crk.connect(hp).connect(crkGain).connect(c.destination); crk.start();
    } else if (!on && crk) {
      const s = crk, g = crkGain; crk = null; crkGain = null;
      g.gain.setValueAtTime(g.gain.value, c.currentTime); g.gain.exponentialRampToValueAtTime(0.0001, c.currentTime + 0.35); s.stop(c.currentTime + 0.4);
    }
  }
  const setSound = (v) => { enabled = !!v; if (!enabled) crackle(false); };
  return { cover, tint, hasCover, pickCover, clearCover, subscribe, needleDrop, crackle, setSound };
})();
