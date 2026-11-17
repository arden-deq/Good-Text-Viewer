document.querySelectorAll("[data-copy]").forEach((button) => {
  if (!navigator.clipboard) return;

  const command = button.parentElement.querySelector("code");
  const status = button.parentElement.querySelector("[role=status]");
  const label = button.textContent;
  let reset;

  button.hidden = false;
  button.addEventListener("click", async () => {
    try {
      await navigator.clipboard.writeText(command.textContent);
      button.textContent = button.dataset.copied;
      status.textContent = button.dataset.copied;
      clearTimeout(reset);
      reset = setTimeout(() => { button.textContent = label; }, 2000);
    } catch {
      status.textContent = button.dataset.copyError;
    }
  });
});

const defaultDownload = document.querySelector('[data-default-download]');
if (defaultDownload) {
  const platform = navigator.userAgentData?.platform || navigator.platform;
  const windows = /^win/i.test(platform);
  const mac = /^mac/i.test(platform) && (navigator.maxTouchPoints ?? 0) <= 1;
  const preferred = windows ? 'Windows' : mac ? 'macOS' : '';
  const downloads = document.querySelector(`[data-platform-download="${preferred}"]`);
  if (downloads) {
    defaultDownload.hidden = true;
    downloads.hidden = false;
  }
}

const demo = document.querySelector("#demo-text");
const controls = document.querySelector(".demo-controls");
if (demo && controls) {
  controls.hidden = false;
  controls.querySelector("[data-demo-size]").addEventListener("input", (event) => {
    demo.style.fontSize = event.target.value + "px";
  });
  controls.querySelector("[data-demo-spacing]").addEventListener("input", (event) => {
    demo.style.letterSpacing = event.target.value + "px";
  });
}

const starCount = document.querySelector('[data-star-count]');
const siteUrl = new URL(location.href);
if (starCount && siteUrl.searchParams.get('github-star') === '1') {
  siteUrl.searchParams.delete('github-star');
  history.replaceState(null, '', siteUrl);
  const query = new URLSearchParams({ page: siteUrl.pathname });
  fetch('/star/result?' + query)
    .then((response) => response.ok ? response.json() : null)
    .then((result) => {
      if (Number.isSafeInteger(result?.stars)) {
        starCount.textContent = result.stars.toLocaleString(document.documentElement.lang);
        starCount.parentElement.hidden = false;
      }
    })
    .catch(() => {});
}

const starButton = document.querySelector('.github-star');
const starPrompt = document.querySelector('[data-star-prompt]');
if (starButton && starPrompt) {
  const dismiss = starPrompt.querySelector('button');
  let downloadButton;

  const positionPrompt = () => {
    if (starPrompt.hidden) return;
    const star = starButton.getBoundingClientRect();
    const width = starPrompt.offsetWidth;
    const center = star.left + star.width / 2;
    const left = Math.max(12, Math.min(center - width / 2, document.documentElement.clientWidth - width - 12));
    starPrompt.style.left = `${left}px`;
    starPrompt.style.top = `${star.bottom + 12}px`;
    starPrompt.style.setProperty('--star-pointer', `${center - left}px`);
  };

  const showPrompt = () => {
    if (starButton.getBoundingClientRect().top < 0) starButton.scrollIntoView({ block: 'nearest' });
    starPrompt.hidden = false;
    starButton.classList.add('star-prompt-target');
    positionPrompt();
  };

  const hidePrompt = () => {
    const restoreFocus = document.activeElement === dismiss;
    starPrompt.hidden = true;
    starButton.classList.remove('star-prompt-target');
    if (restoreFocus) (downloadButton || starButton).focus({ preventScroll: true });
  };

  document.querySelectorAll('[data-star-download]').forEach((link) => {
    if (link.dataset.starDownload === 'archive') {
      const archive = new URL(link.href);
      archive.searchParams.set('star-prompt', '1');
      link.href = archive.href;
      return;
    }
    link.addEventListener('click', () => {
      downloadButton = link;
      showPrompt();
    });
  });

  if (siteUrl.searchParams.get('star-prompt') === '1') {
    siteUrl.searchParams.delete('star-prompt');
    history.replaceState(null, '', siteUrl);
    showPrompt();
  }

  dismiss.addEventListener('click', hidePrompt);
  document.addEventListener('keydown', ({ key }) => {
    if (key === 'Escape' && !starPrompt.hidden) hidePrompt();
  });
  window.addEventListener('resize', positionPrompt);
  window.addEventListener('scroll', positionPrompt, { passive: true });
}
