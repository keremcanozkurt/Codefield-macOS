import assert from "node:assert/strict";
import { describe, it } from "node:test";

import { sharedFaq } from "../upstream/src/lib/product.ts";
import { CONTACT_EMAIL, DONATION_URL, FAQ, SUPPORT_URL } from "./product.ts";

describe("macOS FAQ", () => {
  it("uses the same links and contact as the web edition", () => {
    assert.equal(SUPPORT_URL, "https://codefield.keremcanozkurt.com/support");
    assert.equal(DONATION_URL, "https://codefield.keremcanozkurt.com/donation");
    assert.equal(CONTACT_EMAIL, "hello@keremcanozkurt.com");
  });

  it("includes every shared answer as written", () => {
    for (const entry of Object.values(sharedFaq({ analyzeAgain: "Analyze Again" }))) {
      assert.ok(FAQ.some((faq) => faq.question === entry.question && faq.answer === entry.answer), entry.question);
    }
  });

  it("does not describe the terminal or the local web server", () => {
    for (const entry of FAQ) assert.doesNotMatch(entry.answer, /127\.0\.0\.1|codefield clone|`codefield`/, entry.question);
  });
});
