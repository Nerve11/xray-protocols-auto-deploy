/**
 * Main Application Logic
 */

class XrayDashboard {
  constructor() {
    this.profiles = [];
    this.stats = {};
    this.systemInfo = {};
    this.refreshInterval = null;
    
    this.init();
  }

  async init() {
    // Check API health
    try {
      await api.healthCheck();
      updateConnectionStatus(true);
    } catch (error) {
      updateConnectionStatus(false);
      showToast('Failed to connect to backend', 'error');
    }

    // Load initial data
    await this.loadSystemInfo();
    await this.loadProfiles();
    await this.loadStats();

    // Setup event listeners
    this.setupEventListeners();

    // Start auto-refresh (every 10 seconds)
    this.startAutoRefresh();
  }

  setupEventListeners() {
    // Create profile form
    document.getElementById('create-profile-form').addEventListener('submit', (e) => {
      e.preventDefault();
      this.handleCreateProfile();
    });

    // Refresh button
    document.getElementById('refresh-btn').addEventListener('click', () => {
      this.refresh();
    });

    // Modal close
    document.getElementById('close-modal').addEventListener('click', () => {
      this.closeModal();
    });

    // Close modal on backdrop click
    document.getElementById('qr-modal').addEventListener('click', (e) => {
      if (e.target.id === 'qr-modal') {
        this.closeModal();
      }
    });
  }

  async loadSystemInfo() {
    try {
      this.systemInfo = await api.getSystemInfo();
      document.getElementById('server-ip').textContent = `Server: ${this.systemInfo.server_address || 'N/A'}`;
    } catch (error) {
      console.error('Failed to load system info:', error);
    }
  }

  async loadProfiles() {
    try {
      this.profiles = await api.listProfiles();
      this.renderProfiles();
    } catch (error) {
      showToast('Failed to load profiles', 'error');
      console.error(error);
    }
  }

  async loadStats() {
    try {
      this.stats = await api.getStats();
      this.renderStats();
    } catch (error) {
      console.error('Failed to load stats:', error);
    }
  }

  renderStats() {
    const grid = document.getElementById('stats-grid');
    const { active_connections, total_profiles, uptime_seconds, total_traffic_bytes } = this.stats;

    const stats = [
      { label: 'Active Connections', value: active_connections || 0, icon: 'M13 10V3L4 14h7v7l9-11h-7z' },
      { label: 'Total Profiles', value: total_profiles || 0, icon: 'M17 20h5v-2a3 3 0 00-5.356-1.857M17 20H7m10 0v-2c0-.656-.126-1.283-.356-1.857M7 20H2v-2a3 3 0 015.356-1.857M7 20v-2c0-.656.126-1.283.356-1.857m0 0a5.002 5.002 0 019.288 0M15 7a3 3 0 11-6 0 3 3 0 016 0zm6 3a2 2 0 11-4 0 2 2 0 014 0zM7 10a2 2 0 11-4 0 2 2 0 014 0z' },
      { label: 'Uptime', value: formatUptime(uptime_seconds || 0), icon: 'M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z' },
      { label: 'Traffic', value: formatBytes(total_traffic_bytes || 0), icon: 'M7 16a4 4 0 01-.88-7.903A5 5 0 1115.9 6L16 6a5 5 0 011 9.9M15 13l-3-3m0 0l-3 3m3-3v12' },
    ];

    grid.innerHTML = stats.map(({ label, value, icon }) => `
      <div class="bg-dark-900 rounded-lg p-4 border border-gray-700">
        <div class="flex items-center gap-3">
          <div class="p-2 bg-primary-500/10 rounded-lg">
            <svg class="w-6 h-6 text-primary-500" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="${icon}"></path>
            </svg>
          </div>
          <div class="flex-1">
            <p class="text-sm text-gray-400">${label}</p>
            <p class="text-2xl font-bold mt-1">${value}</p>
          </div>
        </div>
      </div>
    `).join('');
  }

  renderProfiles() {
    const container = document.getElementById('profiles-list');
    const emptyState = document.getElementById('empty-state');
    const countEl = document.getElementById('profile-count');

    countEl.textContent = `(${this.profiles.length})`;

    if (this.profiles.length === 0) {
      container.classList.add('hidden');
      emptyState.classList.remove('hidden');
      return;
    }

    container.classList.remove('hidden');
    emptyState.classList.add('hidden');

    container.innerHTML = this.profiles.map(profile => `
      <div class="bg-dark-900 rounded-lg p-4 border border-gray-700 hover:border-primary-500/50 transition">
        <div class="flex flex-col sm:flex-row sm:items-center justify-between gap-4">
          <div class="flex-1">
            <div class="flex items-center gap-2 mb-2">
              <span class="px-2 py-1 text-xs font-medium rounded bg-primary-500/20 text-primary-400">
                ${profile.protocol.toUpperCase()}
              </span>
              <span class="text-xs text-gray-500">${profile.transport} • ${profile.security}</span>
            </div>
            <p class="font-mono text-sm text-gray-300 mb-1">${truncateUUID(profile.id)}</p>
            <p class="text-sm text-gray-400">${profile.email || 'No email'}</p>
            ${profile.sni ? `<p class="text-xs text-gray-500 mt-1">SNI: ${profile.sni}</p>` : ''}
          </div>
          <div class="flex flex-wrap gap-2">
            <button 
              onclick="app.showQRCode('${profile.id}')"
              class="px-3 py-1.5 text-sm bg-gray-700 hover:bg-gray-600 rounded transition flex items-center gap-2"
              title="Generate QR Code"
            >
              <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 4v1m6 11h2m-6 0h-2v4m0-11v3m0 0h.01M12 12h4.01M16 20h4M4 12h4m12 0h.01M5 8h2a1 1 0 001-1V5a1 1 0 00-1-1H5a1 1 0 00-1 1v2a1 1 0 001 1zm12 0h2a1 1 0 001-1V5a1 1 0 00-1-1h-2a1 1 0 00-1 1v2a1 1 0 001 1zM5 20h2a1 1 0 001-1v-2a1 1 0 00-1-1H5a1 1 0 00-1 1v2a1 1 0 001 1z"></path>
              </svg>
              QR
            </button>
            <button 
              onclick="app.copyProfile('${profile.connection_link}')"
              class="px-3 py-1.5 text-sm bg-gray-700 hover:bg-gray-600 rounded transition flex items-center gap-2"
              title="Copy Connection Link"
            >
              <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8 16H6a2 2 0 01-2-2V6a2 2 0 012-2h8a2 2 0 012 2v2m-6 12h8a2 2 0 002-2v-8a2 2 0 00-2-2h-8a2 2 0 00-2 2v8a2 2 0 002 2z"></path>
              </svg>
              Copy
            </button>
            <button 
              onclick="app.deleteProfile('${profile.id}')"
              class="px-3 py-1.5 text-sm bg-danger-600 hover:bg-danger-700 rounded transition flex items-center gap-2"
              title="Delete Profile"
            >
              <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16"></path>
              </svg>
              Delete
            </button>
          </div>
        </div>
      </div>
    `).join('');
  }

  async handleCreateProfile() {
    const input = document.getElementById('email-input');
    const email = input.value.trim();

    if (!email) {
      showToast('Email is required', 'warning');
      return;
    }

    try {
      const profile = await api.createProfile(email);
      showToast('Profile created successfully!', 'success');
      input.value = '';
      await this.refresh();
    } catch (error) {
      showToast(error.message || 'Failed to create profile', 'error');
    }
  }

  async deleteProfile(profileId) {
    const confirmed = await confirmDialog('Are you sure you want to delete this profile?');
    if (!confirmed) return;

    try {
      await api.deleteProfile(profileId);
      showToast('Profile deleted', 'success');
      await this.refresh();
    } catch (error) {
      showToast(error.message || 'Failed to delete profile', 'error');
    }
  }

  copyProfile(link) {
    copyToClipboard(link);
  }

  async showQRCode(profileId) {
    try {
      const blob = await api.getQRCode(profileId);
      const url = URL.createObjectURL(blob);
      
      const modal = document.getElementById('qr-modal');
      const content = document.getElementById('qr-content');
      
      content.innerHTML = `<img src="${url}" alt="QR Code" class="max-w-full" />`;
      modal.classList.remove('hidden');
      modal.classList.add('flex');
    } catch (error) {
      showToast('Failed to generate QR code', 'error');
    }
  }

  closeModal() {
    const modal = document.getElementById('qr-modal');
    modal.classList.add('hidden');
    modal.classList.remove('flex');
  }

  async refresh() {
    await Promise.all([
      this.loadProfiles(),
      this.loadStats(),
    ]);
    showToast('Refreshed', 'success', 1500);
  }

  startAutoRefresh() {
    this.refreshInterval = setInterval(() => {
      this.loadStats();
    }, 10000); // 10 seconds
  }

  stopAutoRefresh() {
    if (this.refreshInterval) {
      clearInterval(this.refreshInterval);
    }
  }
}

// Initialize app when DOM is ready
let app;
document.addEventListener('DOMContentLoaded', () => {
  app = new XrayDashboard();
});