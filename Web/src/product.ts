// Stands in for upstream lib/product.ts in the app bundle: the FAQ of the
// web edition describes the terminal and the local web server, which the
// macOS app does not have. Answers that are the same on both come from
// upstream. The build also writes this FAQ to faq.json for the app's native
// FAQ window.
import { sharedFaq, type FaqEntry } from "../upstream/src/lib/product.ts";

export {
  CONTACT_EMAIL,
  CONTACT_NOTE,
  CONTACT_TITLE,
  DONATION_LABEL,
  DONATION_NOTE,
  DONATION_URL,
  SITE_URL,
  SUPPORT_URL,
  type FaqEntry,
} from "../upstream/src/lib/product.ts";

const shared = sharedFaq({ analyzeAgain: "Analyze Again" });

export const FAQ: FaqEntry[] = [
  {
    question: "Does my source code leave my Mac?",
    answer:
      "No. Codefield reads the folder on your Mac and analyzes it inside the app. It makes no network requests of its own and collects no analytics. Only Clone Git Repository goes over the network, through your own Git.",
  },
  {
    question: "Which folders can Codefield read?",
    answer:
      "Only the folders you open with Open Repository, drop onto the window, reopen from the recent list, or clone. The app runs in the macOS App Sandbox, which keeps it from reading anything else.",
  },
  shared.runsCode,
  {
    question: "Do I need GitHub?",
    answer:
      "No. Codefield opens any folder on your Mac, whether or not it is a Git repository. To clone a repository, Clone Git Repository uses your installed Git and your existing SSH or credential setup, whatever the host: GitHub, GitLab, Bitbucket, Codeberg, Gitea, Forgejo or your own server.",
  },
  {
    question: "How does Clone Git Repository work?",
    answer:
      "It runs the Git installed on your Mac in a small helper outside the sandbox, so your SSH keys, SSH agent, `~/.ssh/config`, `known_hosts` and credential helpers work as they do in Terminal. Codefield never reads them, never asks for passwords or tokens, and never accepts an unknown SSH host key for you. The clone is an ordinary Git folder where you chose; Codefield never updates or deletes it.",
  },
  {
    question: "Can I analyze private repositories?",
    answer:
      "Yes. Open a repository that is already on your Mac, or clone one with Clone Git Repository: Git uses the credentials you already have, and Codefield never asks for them.",
  },
  shared.commitOrPush,
  shared.watching,
  shared.views,
  shared.impact,
  shared.pathFinder,
  shared.languages,
  {
    question: "Where does Export PNG save the image?",
    answer: "In your Downloads folder.",
  },
  shared.license,
];
