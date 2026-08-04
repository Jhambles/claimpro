import type { Config } from "tailwindcss";

// Design tokens preserved from the original static ClaimsPro prototype
const config: Config = {
  content: ["./src/**/*.{js,ts,jsx,tsx,mdx}"],
  theme: {
    extend: {
      colors: {
        navy: "#0b1d32",
        teal: {
          DEFAULT: "#00a3ad",
          400: "#2dd4dc",
          500: "#00a3ad",
          600: "#008790",
        },
      },
      borderRadius: {
        "4xl": "2rem",
        "5xl": "3rem",
      },
    },
  },
  plugins: [],
};
export default config;
