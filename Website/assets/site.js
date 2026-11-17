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
