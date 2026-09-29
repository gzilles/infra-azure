// Sample data with EXACTLY the same shape the API returns (see API contract).
// Used when ?mock=1 or APP_CONFIG.mock = true. Also the reference for the Cosmos seed.
window.MOCK_DATA = {
  "org-a": {
    posture: {
      organization: { id: "org-a", name: "Organization A" },
      updatedAt: "2026-09-28T12:00:00Z",
      score: 72, previousScore: 78,
      indicators: [
        { key: "vuln-mgmt", name: "Vulnerability Management", score: 58, previousScore: 71, status: "serious", trend: [74, 73, 72, 71, 71, 69, 71, 58] },
        { key: "iam", name: "Identity & Access", score: 81, previousScore: 80, status: "good", trend: [76, 77, 77, 78, 79, 79, 80, 81] },
        { key: "awareness", name: "Security Awareness", score: 66, previousScore: 67, status: "warning", trend: [60, 61, 63, 64, 65, 66, 67, 66] },
        { key: "backup", name: "Backup & Recovery", score: 85, previousScore: 85, status: "good", trend: [82, 83, 83, 84, 84, 85, 85, 85] },
        { key: "logging", name: "Logging & Monitoring", score: 70, previousScore: 77, status: "warning", trend: [75, 76, 76, 77, 77, 77, 77, 70] },
      ],
    },
    controls: {
      "vuln-mgmt": [
        { id: "VM-01", name: "Critical vulnerabilities patched within 15 days", owner: "Infrastructure", dueDate: "2026-09-15", status: "overdue" },
        { id: "VM-02", name: "Authenticated scan of all servers every week", owner: "Security Operations", dueDate: "2026-09-20", status: "overdue" },
        { id: "VM-03", name: "Internet-facing assets inventoried and scanned", owner: "Security Operations", dueDate: "2026-09-22", status: "overdue" },
        { id: "VM-04", name: "KEV-listed vulnerabilities prioritized first", owner: "Vulnerability Team", dueDate: "2026-10-05", status: "at-risk" },
        { id: "VM-05", name: "Exceptions approved by the risk owner", owner: "GRC", dueDate: "2026-10-30", status: "ok" },
        { id: "VM-06", name: "Monthly patch compliance report", owner: "Infrastructure", dueDate: "2026-10-31", status: "ok" },
      ],
      "iam": [
        { id: "IA-01", name: "MFA enforced for all privileged accounts", owner: "Identity Team", dueDate: "2026-10-31", status: "ok" },
        { id: "IA-02", name: "Quarterly access review", owner: "Identity Team", dueDate: "2026-10-10", status: "at-risk" },
        { id: "IA-03", name: "Leavers disabled within 24 hours", owner: "HR + Identity", dueDate: "2026-10-31", status: "ok" },
      ],
      "awareness": [
        { id: "SA-01", name: "Annual security training completed", owner: "HR", dueDate: "2026-11-30", status: "at-risk" },
        { id: "SA-02", name: "Phishing simulation every quarter", owner: "Security Awareness", dueDate: "2026-10-15", status: "ok" },
      ],
      "backup": [
        { id: "BR-01", name: "Daily backups of critical systems", owner: "Infrastructure", dueDate: "2026-10-31", status: "ok" },
        { id: "BR-02", name: "Restore test every quarter", owner: "Infrastructure", dueDate: "2026-12-15", status: "ok" },
      ],
      "logging": [
        { id: "LM-01", name: "Critical systems sending logs to the SIEM", owner: "Security Operations", dueDate: "2026-09-25", status: "overdue" },
        { id: "LM-02", name: "Log retention of at least 12 months", owner: "Security Operations", dueDate: "2026-10-31", status: "ok" },
      ],
    },
  },
  "org-b": {
    posture: {
      organization: { id: "org-b", name: "Organization B" },
      updatedAt: "2026-09-28T12:00:00Z",
      score: 83, previousScore: 81,
      indicators: [
        { key: "vuln-mgmt", name: "Vulnerability Management", score: 79, previousScore: 76, status: "warning", trend: [70, 71, 73, 74, 75, 75, 76, 79] },
        { key: "iam", name: "Identity & Access", score: 88, previousScore: 87, status: "good", trend: [84, 85, 85, 86, 86, 87, 87, 88] },
        { key: "awareness", name: "Security Awareness", score: 74, previousScore: 72, status: "warning", trend: [66, 67, 69, 70, 71, 71, 72, 74] },
        { key: "backup", name: "Backup & Recovery", score: 91, previousScore: 91, status: "good", trend: [89, 90, 90, 90, 91, 91, 91, 91] },
        { key: "logging", name: "Logging & Monitoring", score: 84, previousScore: 81, status: "good", trend: [77, 78, 79, 80, 80, 81, 81, 84] },
      ],
    },
    controls: {
      "vuln-mgmt": [
        { id: "VM-01", name: "Critical vulnerabilities patched within 15 days", owner: "Infrastructure", dueDate: "2026-10-12", status: "at-risk" },
        { id: "VM-02", name: "Authenticated scan of all servers every week", owner: "Security Operations", dueDate: "2026-10-31", status: "ok" },
      ],
      "iam": [
        { id: "IA-01", name: "MFA enforced for all privileged accounts", owner: "Identity Team", dueDate: "2026-10-31", status: "ok" },
      ],
      "awareness": [
        { id: "SA-01", name: "Annual security training completed", owner: "HR", dueDate: "2026-11-30", status: "at-risk" },
      ],
      "backup": [
        { id: "BR-01", name: "Daily backups of critical systems", owner: "Infrastructure", dueDate: "2026-10-31", status: "ok" },
      ],
      "logging": [
        { id: "LM-01", name: "Critical systems sending logs to the SIEM", owner: "Security Operations", dueDate: "2026-10-31", status: "ok" },
      ],
    },
  },
};
