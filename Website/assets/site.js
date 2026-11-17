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
