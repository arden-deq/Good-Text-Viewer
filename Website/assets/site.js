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

const starStatus = document.querySelector('[data-star-status]');
const siteUrl = new URL(location.href);
if (starStatus && siteUrl.searchParams.get('github-star') === '1') {
  siteUrl.searchParams.delete('github-star');
  history.replaceState(null, '', siteUrl);
  const query = new URLSearchParams({ page: siteUrl.pathname });
  fetch('/star/result?' + query)
    .then((response) => {
      if (!response.ok) throw new Error('Star result unavailable');
      return response.json();
    })
    .then(({ status, stars }) => {
      starStatus.textContent = starStatus.dataset[status] || starStatus.dataset.failed;
      if (Number.isSafeInteger(stars)) {
        const count = document.querySelector('[data-star-count]');
        count.textContent = stars.toLocaleString(document.documentElement.lang);
        count.parentElement.hidden = false;
      }
    })
    .catch(() => { starStatus.textContent = starStatus.dataset.failed; });
}
