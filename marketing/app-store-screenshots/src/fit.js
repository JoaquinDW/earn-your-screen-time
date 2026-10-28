// Wait for the bundled fonts, then fit two headline lines and one subline.
// Rendering also validates line count and bounds, so a copy change cannot clip silently.
window.layoutReady = document.fonts.ready.then(() => {
  const headline = document.querySelector('.headline');
  const parts = headline.innerHTML.split('<br>');
  headline.innerHTML = parts.map(part => `<span class="headline-line" style="display:block;white-space:nowrap">${part}</span>`).join('');
  const fit = (element, max, min) => {
    for (let size = max; size >= min; size--) {
      element.style.fontSize = `${size}px`;
      if (element.scrollWidth <= element.clientWidth) return;
    }
    throw new Error(`Copy does not fit: ${element.textContent}`);
  };
  fit(headline, 240, 100);
  fit(document.querySelector('.sub'), 48, 30);
});
