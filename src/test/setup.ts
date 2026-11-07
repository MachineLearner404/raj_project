import "@testing-library/jest-dom/vitest";

// jsdom does not implement matchMedia; next-themes (used for the toast
// theme sync) reads it on mount.
if (!window.matchMedia) {
  window.matchMedia = (query: string) => ({
    matches: false,
    media: query,
    onchange: null,
    addListener: () => {},
    removeListener: () => {},
    addEventListener: () => {},
    removeEventListener: () => {},
    dispatchEvent: () => false,
  });
}
