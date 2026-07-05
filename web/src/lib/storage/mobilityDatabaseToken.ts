// The user's own free Mobility Database refresh token (from their Account
// Details page at mobilitydatabase.org), stored only in their own browser --
// never shipped in this app's bundle. There's no backend here to hold a
// shared secret (confirmed CORS-open API + no anonymous tier means "bring
// your own token, call it directly from the browser" is the only option
// that keeps this app fully static -- see R/mobility_database.R for the
// server-side equivalent this is a client-side counterpart of, and the
// plan file for why a Worker was ruled out).
const STORAGE_KEY = "mobilityDatabaseRefreshToken";

export function getMobilityDatabaseToken(): string | null {
  return localStorage.getItem(STORAGE_KEY);
}

export function setMobilityDatabaseToken(token: string): void {
  localStorage.setItem(STORAGE_KEY, token);
}

export function clearMobilityDatabaseToken(): void {
  localStorage.removeItem(STORAGE_KEY);
}
