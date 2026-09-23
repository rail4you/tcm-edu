// Shared LiveView hooks for the admin & teacher shells.
//
//  * SidebarCollapse — persists the drawer collapse state (icon-only on
//    desktop) via the daisyUI `is-drawer-open:` / `is-drawer-close:`
//    variants; the drawer-toggle checkbox is purely a CSS switch.
//  * ThemeController — persists the daisyUI theme choice and restores it
//    after every LiveView patch / navigation.
//  * PasswordToggle — login password visibility switch (eye / eye-off).
//  * FlashAutoDismiss — auto-dismisses flash notices after a TTL
//    (`data-flash-ttl` ms) by reusing the proven click-to-dismiss path
//    (`lv:clear-flash` + hide), so server-side flash is cleared too.

const SidebarCollapse = {
  mounted() {
    this.key = this.el.dataset.collapseKey || "tcm-sidebar-collapsed";
    this.apply();

    this.el.addEventListener("change", (event) => {
      if (event.target.classList.contains("drawer-toggle")) {
        localStorage.setItem(this.key, event.target.checked ? "1" : "0");
      }
    });
  },
  updated() {
    this.apply();
  },
  apply() {
    const toggle = this.el.querySelector(".drawer-toggle");
    if (!toggle) return;

    if (window.innerWidth < 1024) {
      toggle.checked = false;
      return;
    }

    const saved = localStorage.getItem(this.key);
    toggle.checked = saved === null ? true : saved === "1";
  },
};

const ThemeController = {
  mounted() {
    this.apply();
    this.el.addEventListener("change", (event) => {
      if (event.target.classList.contains("theme-controller") && event.target.checked) {
        localStorage.setItem("tcm-theme", event.target.value);
        document.documentElement.setAttribute("data-theme", event.target.value);
      }
    });
  },
  updated() {
    this.apply();
  },
  apply() {
    const defaultTheme = this.el.dataset.defaultTheme || "light";
    const theme = localStorage.getItem("tcm-theme") || defaultTheme;
    document.documentElement.setAttribute("data-theme", theme);

    const target = this.el.querySelector(`input.theme-controller[value="${theme}"]`);
    if (target && !target.checked) target.checked = true;
  },
};

const PasswordToggle = {
  mounted() {
    const root = this.el;
    const input = root.querySelector("input");
    const btn = root.querySelector("[data-pw-toggle]");
    const eye = root.querySelector("[data-eye]");
    const eyeOff = root.querySelector("[data-eye-off]");
    if (!input || !btn) return;
    btn.addEventListener("click", () => {
      const show = input.type === "password";
      input.type = show ? "text" : "password";
      btn.setAttribute("aria-label", show ? "隐藏密码" : "显示密码");
      if (eye) eye.classList.toggle("hidden", show);
      if (eyeOff) eyeOff.classList.toggle("hidden", !show);
      input.focus();
    });
  },
};

const FlashAutoDismiss = {
  mounted() {
    this.schedule();
  },
  updated() {
    // Flash content re-rendered (e.g. a new message): restart the timer
    // and make sure a previously hidden element is visible again.
    this.el.style.display = "";
    this.el.style.opacity = "";
    this.schedule();
  },
  destroyed() {
    this.clear();
  },
  clear() {
    if (this.timer) {
      clearTimeout(this.timer);
      this.timer = null;
    }
  },
  schedule() {
    this.clear();
    const ttl = parseInt(this.el.dataset.flashTtl || "4000", 10);
    if (!ttl || ttl <= 0) return;
    this.timer = setTimeout(() => {
      // Reuse the proven click-to-dismiss path (lv:clear-flash + hide),
      // so the server-side flash is cleared and won't reappear.
      if (document.contains(this.el)) this.el.click();
    }, ttl);
  },
};

export { SidebarCollapse, ThemeController, PasswordToggle, FlashAutoDismiss };