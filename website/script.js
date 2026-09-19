document.addEventListener("DOMContentLoaded", () => {
  if (window.lucide) {
    window.lucide.createIcons();
  }

  document.querySelectorAll("[data-year]").forEach((element) => {
    element.textContent = new Date().getFullYear();
  });

  const toggle = document.querySelector(".nav-toggle");
  const navigation = document.querySelector(".nav-links");

  if (toggle && navigation) {
    toggle.addEventListener("click", () => {
      const expanded = toggle.getAttribute("aria-expanded") === "true";
      toggle.setAttribute("aria-expanded", String(!expanded));
      toggle.setAttribute("aria-label", expanded ? "打开导航" : "关闭导航");
      navigation.classList.toggle("is-open", !expanded);
    });

    navigation.querySelectorAll("a").forEach((link) => {
      link.addEventListener("click", () => {
        toggle.setAttribute("aria-expanded", "false");
        toggle.setAttribute("aria-label", "打开导航");
        navigation.classList.remove("is-open");
      });
    });
  }

  const diagnostic = document.querySelector("[data-diagnostic]");
  const diagnosticResult = document.querySelector("[data-diagnostic-result]");
  if (diagnostic && diagnosticResult) {
    const advice = {
      full: "先打开“系统设置 → 通用 → 储存空间”确认大类，再优先处理可重新生成的缓存、日志和旧版开发缓存。个人文件不要盲删。",
      system: "“系统数据”不是一个可以直接删除的文件夹。先识别缓存、备份、虚拟机或本地快照等具体来源，再逐项确认。",
      xcode: "在安装了多个 Xcode 运行时的电脑上，先保留每个平台的最新版本，再检查旧版模拟器和可重建的共享缓存。",
      cache: "应用缓存可能会被重新生成。清理前应查看路径、大小和修改时间，优先处理明确属于缓存的目录。"
    };
    diagnostic.addEventListener("submit", (event) => {
      event.preventDefault();
      const selected = diagnostic.querySelector("input[name='storage-problem']:checked");
      if (!selected) return;
      diagnosticResult.innerHTML = `<strong>建议：</strong>${advice[selected.value]} <a class="download-inline" href="downloads/MacSpaceCleaner-1.2.dmg" download>下载 App 扫描本机</a>`;
    });
  }
});
