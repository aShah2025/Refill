export interface Env {
  DONORSCHOOSE_API_KEY?: string;
  AI_PROVIDER?: string;
  OPENROUTER_API_KEY?: string;
  OPENROUTER_MODEL?: string;
  OPENAI_API_KEY?: string;
  OPENAI_MODEL?: string;
  STRIPE_SECRET_KEY?: string;
  STRIPE_SUCCESS_URL?: string;
  STRIPE_CANCEL_URL?: string;
  CHECKOUT_CALLBACK_SCHEME?: string;
  CORS_ALLOWED_ORIGINS?: string;
  API_BEARER_TOKEN?: string;
}

export interface Dependencies {
  fetch: typeof globalThis.fetch;
  now: () => Date;
  randomUUID: () => string;
}

export interface NeedItemDTO {
  name: string;
  quantity: number | null;
  unitPrice: number | null;
  category: string | null;
}

export interface ClassroomNeedDTO {
  sourceId: string;
  sourceName: "DonorsChoose";
  sourceURL: string | null;
  teacherName: string | null;
  teacherPhotoURL: string | null;
  teacherBio: string | null;
  yearsTeaching: number | null;
  schoolName: string | null;
  city: string | null;
  state: string | null;
  zip: string | null;
  schoolType: string | null;
  title: string;
  description: string | null;
  category: string | null;
  gradeLevel: string | null;
  studentCount: number | null;
  items: NeedItemDTO[];
  targetAmount: number | null;
  currentAmount: number | null;
  donorCount: number | null;
  createdAt: string | null;
  deadline: string | null;
  photoURLs: string[];
  status: string | null;
}
