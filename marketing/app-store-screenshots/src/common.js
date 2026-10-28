// Fills every tick meter and puts the island and status bar on every screen.
document.querySelectorAll('.ticks').forEach(t => {
  const n = +t.dataset.n || 46, p = +t.dataset.p;
  for (let i = 0; i < n; i++) { const e = document.createElement('i'); if (i / n < p) e.className = 'on'; t.appendChild(e); }
});
document.querySelectorAll('.pt').forEach(pt => pt.insertAdjacentHTML('beforeend', `
  <div class="island"></div>
  <div class="status"><span>${document.documentElement.lang === 'ar' ? '٩:٤١' : '9:41'}</span><span class="icons">
    <svg width="18" height="12"><rect x="0" y="8" width="3" height="4" rx="1" fill="#fff"/><rect x="5" y="5.5" width="3" height="6.5" rx="1" fill="#fff"/><rect x="10" y="3" width="3" height="9" rx="1" fill="#fff"/><rect x="15" y="0" width="3" height="12" rx="1" fill="#fff"/></svg>
    <svg width="27" height="13"><rect x=".5" y=".5" width="23" height="12" rx="3.5" stroke="#fff" fill="none" opacity=".5"/><rect x="2" y="2" width="17" height="9" rx="2" fill="#fff"/><rect x="25" y="4.5" width="1.5" height="4" rx=".7" fill="#fff" opacity=".5"/></svg>
  </span></div>`));
