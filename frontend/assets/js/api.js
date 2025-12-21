/**
 * API Client for Xray Dashboard
 * Handles all HTTP requests to backend FastAPI
 */

class APIClient {
  constructor(baseURL = '/api') {
    this.baseURL = baseURL;
  }

  async request(endpoint, options = {}) {
    const url = `${this.baseURL}${endpoint}`;
    const config = {
      headers: {
        'Content-Type': 'application/json',
        ...options.headers,
      },
      ...options,
    };

    try {
      const response = await fetch(url, config);
      
      if (!response.ok) {
        const error = await response.json().catch(() => ({
          detail: `HTTP ${response.status}: ${response.statusText}`
        }));
        throw new Error(error.detail || 'Request failed');
      }

      // Handle 204 No Content
      if (response.status === 204) {
        return null;
      }

      return await response.json();
    } catch (error) {
      console.error(`API Error [${endpoint}]:`, error);
      throw error;
    }
  }

  // Profile Management
  async listProfiles() {
    return this.request('/profiles');
  }

  async getProfile(profileId) {
    return this.request(`/profiles/${profileId}`);
  }

  async createProfile(email) {
    return this.request('/profiles', {
      method: 'POST',
      body: JSON.stringify({ email }),
    });
  }

  async deleteProfile(profileId) {
    return this.request(`/profiles/${profileId}`, {
      method: 'DELETE',
    });
  }

  async getQRCode(profileId) {
    const response = await fetch(`${this.baseURL}/profiles/${profileId}/qr`);
    if (!response.ok) {
      throw new Error('Failed to generate QR code');
    }
    return response.blob();
  }

  // Statistics
  async getStats() {
    return this.request('/stats');
  }

  async getSystemInfo() {
    return this.request('/system');
  }

  // Configuration
  async createBackup() {
    return this.request('/backup');
  }

  async restoreBackup(backupFile) {
    return this.request('/restore', {
      method: 'POST',
      body: JSON.stringify({ backup_file: backupFile }),
    });
  }

  // Health Check
  async healthCheck() {
    return this.request('/health');
  }
}

// Export singleton instance
const api = new APIClient();