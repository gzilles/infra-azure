// Runtime configuration. The only file that changes per environment.
window.APP_CONFIG = {
  // Base URL of the Posture API (Function App). No trailing slash.
  apiBase: "https://func-meuapp-dev-brs.azurewebsites.net/api",
  // "dev-anonymous": no sign-in, organization chosen in the page (DEV ONLY, fictitious data).
  // "entra": sign-in with Entra ID; the organization comes from the token (not implemented yet).
  authMode: "dev-anonymous",
  defaultOrg: "org-a",
  // true = use mock-data.js instead of calling the API. Also enabled with ?mock=1 in the URL.
  mock: false,
  timeoutMs: 15000,
};
