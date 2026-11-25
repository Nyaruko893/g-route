import { z } from 'zod';

export const IpKindSchema = z.enum(['isp', 'hosting', 'cdn_proxy', 'business', 'unknown']);
export type IpKind = z.infer<typeof IpKindSchema>;

export const BaselineResponseSchema = z.object({
  ip: z.string(),
  country: z.string().nullable(),
  region: z.string().nullable(),
  city: z.string().nullable(),
  asn: z.number().int().nullable(),
  asOrganization: z.string().nullable(),
  colo: z.string().nullable(),
  httpProtocol: z.string().nullable(),
  tlsVersion: z.string().nullable(),
  githubRepoUrl: z.string().nullable(),
  isLocalDev: z.boolean(),
});
export type BaselineResponse = z.infer<typeof BaselineResponseSchema>;

export const IpMetaResponseSchema = z.object({
  ip: z.string(),
  version: z.union([z.literal(4), z.literal(6)]),
  country: z.string().nullable(),
  rirCountry: z.string().nullable(),
  rir: z.string().nullable(),
  city: z.string().nullable(),
  asn: z.number().int().nullable(),
  org: z.string().nullable(),
  ipKind: IpKindSchema,
  broadcastDrift: z.boolean(),
  source: z.string(),
  cached: z.boolean(),
});
export type IpMetaResponse = z.infer<typeof IpMetaResponseSchema>;
