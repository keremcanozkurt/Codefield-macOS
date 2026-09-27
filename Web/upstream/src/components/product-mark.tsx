import { CodefieldMark, CodefieldWordmark } from "@/components/codefield-logo";

export function ProductMark({ size = "small" }: { size?: "small" | "large" }) {
  const large = size === "large";
  return (
    <span className={`inline-flex items-center text-foreground ${large ? "gap-4 sm:gap-5" : "gap-2"}`}>
      <CodefieldMark className={large ? "h-12 w-auto sm:h-15" : "h-[18px] w-auto"} />
      <CodefieldWordmark className={large ? "h-8 w-auto sm:h-10" : "h-3 w-auto"} />
      <span className="sr-only">Codefield</span>
    </span>
  );
}
