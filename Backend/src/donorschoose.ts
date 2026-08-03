import { ApiError, fetchWithTimeout, isRecord } from "./http";
import type { ClassroomNeedDTO, Dependencies, Env, NeedItemDTO } from "./types";

const DONORSCHOOSE_URL = "https://api.donorschoose.org/common/json_feed.html";
const ALLOWED_QUERY_PARAMETERS = new Set(["state", "zip", "q", "max"]);

export async function getNeeds(
  requestURL: URL,
  env: Env,
  dependencies: Dependencies,
): Promise<{ needs: ClassroomNeedDTO[]; source: "donorschoose"; fetchedAt: string }> {
  const apiKey = env.DONORSCHOOSE_API_KEY?.trim();
  if (!apiKey) {
    throw new ApiError(503, "integration_unavailable", "The classroom-needs integration is not configured.");
  }

  for (const key of requestURL.searchParams.keys()) {
    if (!ALLOWED_QUERY_PARAMETERS.has(key)) {
      throw new ApiError(400, "invalid_query", "The request contains an unsupported query parameter.");
    }
  }

  const requestedState = (requestURL.searchParams.get("state") ?? "CA").trim().toUpperCase();
  if (requestedState !== "CA") {
    throw new ApiError(400, "invalid_state", "Only California projects are supported.");
  }

  const zip = validateCaliforniaZIP(requestURL.searchParams.get("zip"));
  const query = validateQuery(requestURL.searchParams.get("q"));
  const max = validateMax(requestURL.searchParams.get("max"));

  const upstreamURL = new URL(DONORSCHOOSE_URL);
  upstreamURL.searchParams.set("APIKey", apiKey);
  upstreamURL.searchParams.set("state", "CA");
  upstreamURL.searchParams.set("max", String(max));
  upstreamURL.searchParams.set("showSynopsis", "true");
  upstreamURL.searchParams.set("includeResources", "true");
  const keywords = [query, zip].filter((value): value is string => Boolean(value));
  if (keywords.length > 0) upstreamURL.searchParams.set("keywords", keywords.join(" "));

  const response = await fetchWithTimeout(
    dependencies.fetch,
    upstreamURL,
    { headers: { Accept: "application/json" } },
    15_000,
  );
  if (!response.ok) {
    throw new ApiError(502, "provider_error", "The classroom-needs provider rejected the request.");
  }

  let payload: unknown;
  try {
    payload = JSON.parse(await response.text());
  } catch {
    throw new ApiError(502, "invalid_provider_response", "The classroom-needs provider returned invalid data.");
  }
  if (!isRecord(payload) || !Array.isArray(payload.proposals)) {
    throw new ApiError(502, "invalid_provider_response", "The classroom-needs provider returned invalid data.");
  }

  const needs = payload.proposals
    .filter(isRecord)
    .map(normalizeProposal)
    .filter((need): need is ClassroomNeedDTO => need !== null)
    .filter((need) => need.state?.toUpperCase() === "CA")
    .filter((need) => !zip || need.zip?.slice(0, 5) === zip)
    .slice(0, max);

  return {
    needs,
    source: "donorschoose",
    fetchedAt: dependencies.now().toISOString(),
  };
}

function validateCaliforniaZIP(value: string | null): string | null {
  if (value === null || value.trim() === "") return null;
  const zip = value.trim();
  if (!/^\d{5}$/.test(zip)) {
    throw new ApiError(400, "invalid_zip", "zip must be a five-digit California ZIP code.");
  }
  const numeric = Number(zip);
  if (numeric < 90001 || numeric > 96162) {
    throw new ApiError(400, "invalid_zip", "zip must be a California ZIP code.");
  }
  return zip;
}

function validateQuery(value: string | null): string | null {
  if (value === null || value.trim() === "") return null;
  const query = value.trim();
  if (query.length > 100 || /[\u0000-\u001F\u007F]/u.test(query)) {
    throw new ApiError(400, "invalid_query", "q must be at most 100 characters without control characters.");
  }
  return query;
}

function validateMax(value: string | null): number {
  if (value === null || value === "") return 20;
  if (!/^\d+$/.test(value)) {
    throw new ApiError(400, "invalid_max", "max must be an integer from 1 through 50.");
  }
  const max = Number(value);
  if (max < 1 || max > 50) {
    throw new ApiError(400, "invalid_max", "max must be an integer from 1 through 50.");
  }
  return max;
}

function normalizeProposal(raw: Record<string, unknown>): ClassroomNeedDTO | null {
  const sourceId = cleanScalar(raw.id, 80);
  const title = cleanText(raw.title, 160);
  if (!sourceId || !/^\d+$/.test(sourceId) || !title) return null;

  const targetAmount = finiteNumber(raw.totalPrice, 0, 10_000_000);
  const remainingAmount = finiteNumber(raw.costToComplete, 0, 10_000_000);
  const currentAmount = targetAmount === null || remainingAmount === null
    ? null
    : roundCurrency(Math.max(0, Math.min(targetAmount, targetAmount - remainingAmount)));

  const imageURL = safeHTTPSURL(raw.imageURL);
  const thankYouPhotos = isRecord(raw.thankYouAssets) && Array.isArray(raw.thankYouAssets.photos)
    ? raw.thankYouAssets.photos.map(safeHTTPSURL).filter((value): value is string => value !== null)
    : [];

  return {
    sourceId,
    sourceName: "DonorsChoose",
    sourceURL: safeDonorsChooseURL(raw.proposalURL),
    teacherName: cleanText(raw.teacherName, 120),
    // The listing API's imageURL is a classroom/project photo, not a teacher headshot.
    teacherPhotoURL: null,
    teacherBio: null,
    yearsTeaching: null,
    schoolName: cleanText(raw.schoolName, 160),
    city: cleanText(raw.city, 100),
    state: cleanScalar(raw.state, 2)?.toUpperCase() ?? null,
    zip: cleanScalar(raw.zip, 10),
    schoolType: normalizeNamedValue(raw.schoolType),
    title,
    description: cleanText(raw.synopsis, 5_000) ?? cleanText(raw.shortDescription, 2_000),
    category: normalizeNamedValue(raw.resource) ?? normalizeNamedValue(raw.subject),
    gradeLevel: normalizeGradeLevel(raw.gradeLevel),
    studentCount: null,
    items: normalizeItems(raw),
    targetAmount: targetAmount === null ? null : roundCurrency(targetAmount),
    currentAmount,
    donorCount: finiteInteger(raw.numDonors, 0, 10_000_000),
    createdAt: normalizeDate(raw.datePosted ?? raw.creationDate ?? raw.createdAt),
    deadline: normalizeDate(raw.expirationDate),
    photoURLs: Array.from(new Set([imageURL, ...thankYouPhotos].filter((value): value is string => value !== null))).slice(0, 10),
    status: normalizeStatus(raw.fundingStatus, remainingAmount),
  };
}

function normalizeItems(raw: Record<string, unknown>): NeedItemDTO[] {
  const candidates = [raw.items, raw.resources, raw.materials].find(Array.isArray);
  if (!Array.isArray(candidates)) return [];
  return candidates.filter(isRecord).flatMap((item) => {
    const name = cleanText(item.name ?? item.itemName ?? item.description, 200);
    if (!name) return [];
    return [{
      name,
      quantity: finiteInteger(item.quantity ?? item.qty, 1, 10_000),
      unitPrice: finiteNumber(item.unitPrice ?? item.price ?? item.unit_price, 0, 1_000_000),
      category: cleanText(item.category ?? item.type, 100),
    }];
  }).slice(0, 100);
}

function normalizeGradeLevel(value: unknown): string | null {
  if (!isRecord(value)) return cleanText(value, 80);
  const candidates = [cleanText(value.name, 80), cleanText(value.id, 80)].filter((item): item is string => Boolean(item));
  return candidates.find((item) => /[A-Za-z]/.test(item)) ?? candidates[0] ?? null;
}

function normalizeNamedValue(value: unknown): string | null {
  if (isRecord(value)) return cleanText(value.name, 100) ?? cleanText(value.id, 100);
  return cleanText(value, 100);
}

function normalizeStatus(value: unknown, remainingAmount: number | null): string | null {
  const raw = cleanScalar(value, 40)?.toLowerCase();
  if (raw === "needs funding" || raw === "open") return "open";
  if (raw === "funded" || raw === "complete" || raw === "completed") return "funded";
  if (remainingAmount !== null) return remainingAmount <= 0 ? "funded" : "open";
  return raw ?? null;
}

function normalizeDate(value: unknown): string | null {
  const string = cleanScalar(value, 80);
  if (!string) return null;
  const timestamp = Date.parse(string);
  return Number.isFinite(timestamp) ? new Date(timestamp).toISOString() : null;
}

function cleanScalar(value: unknown, maxLength: number): string | null {
  if (typeof value !== "string" && typeof value !== "number") return null;
  const normalized = String(value).trim();
  if (!normalized) return null;
  return normalized.slice(0, maxLength);
}

function cleanText(value: unknown, maxLength: number): string | null {
  const scalar = cleanScalar(value, maxLength * 2);
  if (!scalar) return null;
  return decodeEntities(scalar.replace(/<br\s*\/?>/gi, "\n").replace(/<[^>]+>/g, " "))
    .replace(/[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F]/g, "")
    .replace(/[ \t]+/g, " ")
    .replace(/\n{3,}/g, "\n\n")
    .trim()
    .slice(0, maxLength) || null;
}

function decodeEntities(value: string): string {
  const named: Record<string, string> = {
    amp: "&", apos: "'", gt: ">", lt: "<", quot: "\"", nbsp: " ",
  };
  return value.replace(/&(#x[0-9a-f]+|#\d+|[a-z]+);/gi, (match, entity: string) => {
    if (entity.startsWith("#x") || entity.startsWith("#")) {
      const radix = entity.startsWith("#x") ? 16 : 10;
      const digits = entity.startsWith("#x") ? entity.slice(2) : entity.slice(1);
      const codePoint = Number.parseInt(digits, radix);
      return Number.isInteger(codePoint) && codePoint >= 0 && codePoint <= 0x10ffff && !(codePoint >= 0xd800 && codePoint <= 0xdfff)
        ? String.fromCodePoint(codePoint)
        : match;
    }
    return named[entity.toLowerCase()] ?? match;
  });
}

function finiteNumber(value: unknown, min: number, max: number): number | null {
  const number = typeof value === "number" ? value : typeof value === "string" && value.trim() !== "" ? Number(value) : Number.NaN;
  return Number.isFinite(number) && number >= min && number <= max ? number : null;
}

function finiteInteger(value: unknown, min: number, max: number): number | null {
  const number = finiteNumber(value, min, max);
  return number !== null && Number.isInteger(number) ? number : null;
}

function roundCurrency(value: number): number {
  return Math.round(value * 100) / 100;
}

function safeHTTPSURL(value: unknown): string | null {
  const string = cleanScalar(value, 2_048);
  if (!string) return null;
  try {
    const url = new URL(string);
    return url.protocol === "https:" ? url.toString() : null;
  } catch {
    return null;
  }
}

function safeDonorsChooseURL(value: unknown): string | null {
  const urlString = safeHTTPSURL(value);
  if (!urlString) return null;
  const url = new URL(urlString);
  return url.hostname === "donorschoose.org" || url.hostname.endsWith(".donorschoose.org")
    ? url.toString()
    : null;
}
