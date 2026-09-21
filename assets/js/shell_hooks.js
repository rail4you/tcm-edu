// Shared LiveView hooks for the admin & teacher shells.
//
//  * SidebarCollapse — persists the drawer collapse state (icon-only on
//    desktop) via the daisyUI `is-drawer-open:` / `is-drawer-close:`
//    variants; the drawer-toggle checkbox is purely a CSS switch.
//  * ThemeController — persists the daisyUI theme choice and restores it
//    after every LiveView patch / navigation.

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

export { SidebarCollapse, ThemeController };