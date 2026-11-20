(function () {
  "use strict";

  const list = document.getElementById("package-list");
  const summary = document.getElementById("package-summary");
  const isLocalPreview = ["127.0.0.1", "localhost"].includes(
    window.location.hostname
  );

  const fallback = [
    {
      Package: "hostnamefetch",
      Version: "2026.11.21-1",
      Architecture: "all",
      Description: "Neofetch-style system information tool with a hostname banner.",
      Filename: ""
    }
  ];

  function escapeHtml(value) {
    return String(value || "").replace(/[&<>"']/g, function (char) {
      return {
        "&": "&amp;",
        "<": "&lt;",
        ">": "&gt;",
        '"': "&quot;",
        "'": "&#39;"
      }[char];
    });
  }

  function parsePackages(text) {
    return text
      .trim()
      .split(/\n\s*\n/)
      .filter(Boolean)
      .map(function (block) {
        const fields = {};
        let current = "";

        block.split("\n").forEach(function (line) {
          if (/^\s/.test(line) && current) {
            if (current !== "Description") {
              fields[current] += " " + line.trim();
            }
            return;
          }

          const match = line.match(/^([^:]+):\s*(.*)$/);
          if (!match) {
            return;
          }

          current = match[1];
          fields[current] = match[2];
        });

        return fields;
      })
      .filter(function (pkg) {
        return pkg.Package && pkg.Version;
      });
  }

  function renderPackages(packages) {
    if (!packages.length) {
      summary.textContent = "当前索引没有软件包。";
      return;
    }

    list.innerHTML = packages
      .map(function (pkg, index) {
        const name = escapeHtml(pkg.Package);
        const version = escapeHtml(pkg.Version);
        const arch = escapeHtml(pkg.Architecture || "all");
        const description = escapeHtml(pkg.Description || "No description provided.");
        const filename = escapeHtml(pkg.Filename || "");
        const command = "sudo apt install " + pkg.Package;
        const nameMarkup = filename
          ? '<a href="' + filename + '">' + name + "</a>"
          : name;

        return (
          '<article class="package-row" data-package-row>' +
          '<span class="package-index">' + String(index + 1).padStart(2, "0") + "</span>" +
          '<div class="package-main">' +
          "<h3>" + nameMarkup + "</h3>" +
          '<p class="package-description">' + description + "</p>" +
          "</div>" +
          '<div class="package-meta">' +
          "<span>" + version + "</span>" +
          "<span>" + arch + "</span>" +
          "</div>" +
          '<div class="package-action">' +
          "<code>" + escapeHtml(command) + "</code>" +
          '<button class="copy-button copy-compact" type="button" data-copy-value="' +
          escapeHtml(command) +
          '">复制</button>' +
          "</div>" +
          "</article>"
        );
      })
      .join("");

    summary.textContent =
      packages.length + " 个软件包 · stable / main";
  }

  async function loadPackages() {
    try {
      const response = await fetch("dists/stable/main/binary-all/Packages", {
        cache: "no-store"
      });

      if (!response.ok) {
        throw new Error("HTTP " + response.status);
      }

      const packages = parsePackages(await response.text());
      renderPackages(packages);
    } catch (error) {
      renderPackages(fallback);
      summary.textContent = isLocalPreview
        ? "本地预览 · 示例索引"
        : "软件包索引读取失败";
    }
  }

  async function copyText(text) {
    if (navigator.clipboard && window.isSecureContext) {
      await navigator.clipboard.writeText(text);
      return;
    }

    const textarea = document.createElement("textarea");
    textarea.value = text;
    textarea.setAttribute("readonly", "");
    textarea.style.position = "fixed";
    textarea.style.opacity = "0";
    document.body.appendChild(textarea);
    textarea.select();
    document.execCommand("copy");
    textarea.remove();
  }

  document.addEventListener("click", async function (event) {
    const button = event.target.closest(
      "button[data-copy-target], button[data-copy-value]"
    );

    if (!button) {
      return;
    }

    const target = button.dataset.copyTarget
      ? document.getElementById(button.dataset.copyTarget)
      : null;
    const text = button.dataset.copyValue || (target ? target.innerText : "");
    const original = button.textContent;

    try {
      await copyText(text);
      button.textContent = "已复制";
      button.classList.add("is-copied");
      window.setTimeout(function () {
        button.textContent = original;
        button.classList.remove("is-copied");
      }, 1600);
    } catch (error) {
      button.textContent = "复制失败";
      window.setTimeout(function () {
        button.textContent = original;
      }, 1600);
    }
  });

  loadPackages();
})();
