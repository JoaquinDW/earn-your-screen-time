import { HttpError } from "./response.ts";

const LOCALE = /^[A-Za-z]{2,3}(?:-[A-Za-z0-9]{2,8})*$/;

export function validateStudySource(
  sourceText: string | undefined,
  localeValue: string | undefined,
  minimumLength: number,
  maximumLength: number,
): { sourceText: string; locale: string } {
  const trimmedSource = sourceText?.trim();
  if (
    !trimmedSource || trimmedSource.length < minimumLength ||
    trimmedSource.length > maximumLength
  ) {
    throw new HttpError(
      400,
      "invalid_source_text",
      `source_text must contain ${minimumLength} to ${maximumLength} characters`,
    );
  }
  const locale = localeValue?.trim();
  if (!locale || !LOCALE.test(locale)) {
    throw new HttpError(
      400,
      "invalid_locale",
      "locale must be a valid BCP 47 language tag",
    );
  }
  return { sourceText: trimmedSource, locale };
}
