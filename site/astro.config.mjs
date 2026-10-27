import { defineConfig } from "astro/config";
import tailwindcss from "@tailwindcss/vite";
import { wgslVitePlugin } from "@vgpu/wgsl/loader-vite";

// Fully static: the Worker only serves files (see wrangler.jsonc), no SSR adapter needed.
export default defineConfig({
  site: "https://deployedyet.com",
  trailingSlash: "never", // /privacy, never /privacy/ (wrangler.jsonc drops the slash to match)
  // vgpu only takes prepared shaders; the plugin turns .wgsl imports into them at build time.
  // Never inline scripts or assets: the CSP in public/_headers only allows script files from this origin.
  vite: { plugins: [tailwindcss(), wgslVitePlugin()], build: { assetsInlineLimit: 0 } },
});
