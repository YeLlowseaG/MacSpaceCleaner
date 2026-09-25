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
    const isEnglish = document.documentElement.lang.toLowerCase().startsWith("en");
    const downloadHref = isEnglish ? "../downloads/MacSpaceCleaner-1.3.dmg" : "downloads/MacSpaceCleaner-1.3.dmg";
    const advice = {
      full: {
        title: "先确认空间被哪一类内容占用",
        steps: [
          "打开“系统设置 → 通用 → 储存空间”，看看应用、文稿、系统数据中哪一项最大。",
          "优先处理可以重新生成的缓存、日志和旧版开发工具缓存，这些内容通常比个人文件更适合先清理。",
          "下载、照片、iCloud 和聊天数据可能无法恢复，删除前请先打开确认，重要内容先备份。"
        ]
      },
      system: {
        title: "不要把“系统数据”当成一个文件夹直接删除",
        steps: [
          "“系统数据”只是 macOS 的统计分类，里面可能包含应用缓存、日志、iPhone 或 iPad 备份、虚拟机和本地快照。",
          "先找出具体来源和路径，再判断它是否可以重新生成；看不懂的系统目录不要手动删除。",
          "如果占用主要来自缓存，可以用 App 查看已知缓存项目；个人备份和虚拟机文件仍需你自行确认。"
        ]
      },
      xcode: {
        title: "先保留仍在使用的模拟器，再处理旧版本",
        steps: [
          "确认当前项目需要哪些 iOS、watchOS 或其他平台运行时，每个平台至少保留一个正在使用的最新版本。",
          "旧版模拟器运行时和可重建的共享缓存通常占用较大，可以在确认版本后再清理。",
          "以后继续使用 Xcode 时，部分缓存会自动重新生成；需要的运行时也可以重新下载。"
        ]
      },
      cache: {
        title: "只清理明确属于缓存、并且可以重新生成的内容",
        steps: [
          "先查看缓存对应的软件、文件路径、大小和修改时间，确认它不是下载文件、聊天记录或项目文件。",
          "清理缓存通常不会删除账号和个人文档，但软件下次打开时可能需要重新加载或下载资源。",
          "不确定的项目先不要勾选；可以先关闭相关软件，再清理已经确认的缓存。"
        ]
      }
    };
    const englishAdvice = {
      full: {
        title: "First find out what kind of content is using the space",
        steps: [
          "Open System Settings → General → Storage and check whether Applications, Documents or System Data is largest.",
          "Start with regenerable caches, logs and old developer-tool caches; these are usually safer to review before personal files.",
          "Downloads, photos, iCloud files and chat data may not be recoverable. Open and confirm them first, and back up anything important."
        ]
      },
      system: {
        title: "Do not treat System Data as one folder to delete",
        steps: [
          "System Data is a macOS storage category. It may include app caches, logs, iPhone or iPad backups, virtual machines and local snapshots.",
          "Find the actual source and path, then decide whether it can be regenerated. Do not manually remove system directories you do not recognize.",
          "If caches are the main source, use the app to review known cache items. Backups and virtual machine files still require your own confirmation."
        ]
      },
      xcode: {
        title: "Keep the simulators you still use, then review older versions",
        steps: [
          "Check which iOS, watchOS or other platform runtimes your projects need. Keep at least one current runtime for each platform you use.",
          "Old simulator runtimes and regenerable shared caches can be large. Review the version and platform before cleaning them.",
          "Some caches will be rebuilt as you keep using Xcode. Required runtimes can also be downloaded again."
        ]
      },
      cache: {
        title: "Only clean content that is clearly regenerable cache",
        steps: [
          "Check the related app, path, size and modification date. Make sure the item is not a download, chat record or project file.",
          "Clearing a cache normally does not remove accounts or personal documents, but the app may need to reload or download resources next time.",
          "Leave anything uncertain unchecked. You can close the related app first and clean only items you have confirmed."
        ]
      }
    };
    const localizedAdvice = isEnglish ? englishAdvice : advice;
    diagnostic.addEventListener("submit", (event) => {
      event.preventDefault();
      const selected = diagnostic.querySelector("input[name='storage-problem']:checked");
      if (!selected) return;
      const result = localizedAdvice[selected.value];
      const downloadText = isEnglish ? "Download the app to review cleanable items on your Mac" : "下载 App，在本机查看可清理项目";
      diagnosticResult.innerHTML = `<strong>${result.title}</strong><ol>${result.steps.map((step) => `<li>${step}</li>`).join("")}</ol><p><a class="download-inline" href="${downloadHref}" download>${downloadText}</a></p>`;
    });
  }
});
