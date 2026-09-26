// Stands in for upstream lib/product.ts in the app bundle: the FAQ of the
// web edition describes the terminal and the local web server, which the
// macOS app does not have.
import { LANGUAGES } from "../upstream/src/lib/languages/registry.ts";

export const SUPPORT_URL = "https://codefield.keremcanozkurt.com/support";
export const SUPPORT_NOTE = "Codefield is free for personal use. Support its continued development.";

export type FaqEntry = {
  question: string;
  // Text in `backticks` is shown as code.
  answer: string;
};

const strong = LANGUAGES.filter((language) => language.strength === "strong").map((language) => language.name);
const conservative = LANGUAGES.filter((language) => language.strength === "conservative").map((language) => language.name);

export const FAQ: FaqEntry[] = [
  {
    question: "Does my source code leave my Mac?",
    answer:
      "No. Codefield reads the folder on your Mac and analyzes it inside the app. It makes no network requests of its own and collects no analytics.",
  },
  {
    question: "Which folders can Codefield read?",
    answer:
      "Only the folders you open with Open Repository, drop onto the window, or reopen from the recent list. The app runs in the macOS App Sandbox, which keeps it from reading anything else.",
  },
  {
    question: "Does Codefield run code from the repository?",
    answer:
      "No. Source and configuration files are read as text. Codefield never runs scripts, builds the project or runs `git` on it; the branch shown next to the name is read from the files in `.git`.",
  },
  {
    question: "Do I need GitHub?",
    answer: "No. Codefield opens any folder on your Mac, whether or not it is a Git repository.",
  },
  {
    question: "Can I analyze private repositories?",
    answer:
      "Yes. Clone the repository with Git as you normally do, then open the folder. Codefield never asks for credentials.",
  },
  {
    question: "Do I need to commit or push changes before Codefield sees them?",
    answer: "No. Codefield analyzes the files currently on disk. Use Analyze Again after making changes.",
  },
  {
    question: "Does Codefield watch files automatically?",
    answer: "Not currently. Use Analyze Again to read the folder again.",
  },
  {
    question: "What do Graph and Structure mean?",
    answer:
      "Graph shows how the files depend on each other. Structure shows where the files and directories are in the repository. Both share the selection, search and filters.",
  },
  {
    question: "What does Impact Mode mean?",
    answer:
      "It lists the files that could be affected by changing the selected file, according to the static dependency graph. It is not a guarantee of what happens at runtime.",
  },
  {
    question: "What does Path Finder mean?",
    answer:
      "It finds the shortest directed chain of dependencies from one file to another in the static graph. A → B means A imports B.",
  },
  {
    question: "Which languages are supported?",
    answer: `${list(strong)} are resolved strongly: they name files or modules directly, so most dependencies show up. ${list(conservative)} are resolved conservatively: they mostly import namespaces or packages, so only references that map to exactly one file are kept.`,
  },
  {
    question: "Where does Export PNG save the image?",
    answer: "In your Downloads folder.",
  },
  {
    question: "Is the source available?",
    answer:
      "Yes. Codefield is source-available: you can read, fork and modify it for personal and non-commercial use under the PolyForm Noncommercial license, and contributions are welcome. Commercial use needs the author's permission. See LICENSE in the repository for the full terms.",
  },
];

function list(names: string[]): string {
  return `${names.slice(0, -1).join(", ")} and ${names.at(-1)}`;
}
