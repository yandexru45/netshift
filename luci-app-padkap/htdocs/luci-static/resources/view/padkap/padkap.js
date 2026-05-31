"use strict";
"require view";
"require form";
"require baseclass";
"require network";
"require view.padkap.main as main";

// Settings content
"require view.padkap.settings as settings";

// Sections content
"require view.padkap.section as section";

// Dashboard content
"require view.padkap.dashboard as dashboard";

// Diagnostic content
"require view.padkap.diagnostic as diagnostic";

const EntryPoint = {
  async render() {
    main.injectGlobalStyles();

    const padkapMap = new form.Map(
      "padkap",
      _("Padkap Settings"),
      _("Configuration for Padkap service"),
    );
    // Enable tab views
    padkapMap.tabbed = true;

    // Sections tab
    const sectionsSection = padkapMap.section(
      form.TypedSection,
      "section",
      _("Sections"),
    );
    sectionsSection.anonymous = false;
    sectionsSection.addremove = true;
    sectionsSection.template = "cbi/simpleform";

    // Render section content
    section.createSectionContent(sectionsSection);

    // Settings tab
    const settingsSection = padkapMap.section(
      form.TypedSection,
      "settings",
      _("Settings"),
    );
    settingsSection.anonymous = true;
    settingsSection.addremove = false;
    // Make it named [ config settings 'settings' ]
    settingsSection.cfgsections = function () {
      return ["settings"];
    };

    // Render settings content
    settings.createSettingsContent(settingsSection);

    // Diagnostic tab
    const diagnosticSection = padkapMap.section(
      form.TypedSection,
      "diagnostic",
      _("Diagnostics"),
    );
    diagnosticSection.anonymous = true;
    diagnosticSection.addremove = false;
    diagnosticSection.cfgsections = function () {
      return ["diagnostic"];
    };

    // Render diagnostic content
    diagnostic.createDiagnosticContent(diagnosticSection);

    // Dashboard tab
    const dashboardSection = padkapMap.section(
      form.TypedSection,
      "dashboard",
      _("Dashboard"),
    );
    dashboardSection.anonymous = true;
    dashboardSection.addremove = false;
    dashboardSection.cfgsections = function () {
      return ["dashboard"];
    };

    // Render dashboard content
    dashboard.createDashboardContent(dashboardSection);

    // Inject core service
    main.coreService();

    return padkapMap.render();
  },
};

return view.extend(EntryPoint);
