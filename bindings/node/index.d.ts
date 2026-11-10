/** A segment of the reading and its candidates, best first. */
export interface Segment {
  reading: string;
  candidates: string[];
}

export const ABI_VERSION: number;

/** One Mozc engine. Call close() (or use `using`) to save what was learned and free it. */
export class Mozc {
  /**
   * @param profileDir where Mozc keeps what it learns; null for Mozc's default
   * @param options.incognito learn nothing and leave the profile untouched
   */
  constructor(profileDir?: string | null, options?: { incognito?: boolean });
  /** Mozc's version, such as "2.32.5994.102". */
  static readonly mozcVersion: string;
  /** Why the last convert, predict, learn, clearLearning or flush failed; '' if it succeeded. */
  readonly lastError: string;
  /** Segments of the reading; lengths (in characters) fix the segments; context is the text before it. */
  convert(reading: string, lengths?: number[] | null, context?: string): Segment[];
  /** Completions of the reading typed so far. */
  predict(reading: string, context?: string): string[];
  /** Learns the picked texts, one per segment of lengths; false (nothing learned) on a mismatch. */
  learn(reading: string, lengths: number[], texts: string[], context?: string): boolean;
  /** Forgets everything learned. */
  clearLearning(): boolean;
  /** Writes what was learned to the profile. */
  flush(): boolean;
  /** Saves what was learned and frees the engine. */
  close(): void;
  [Symbol.dispose](): void;
}
