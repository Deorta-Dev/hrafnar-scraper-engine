import { Injectable } from '@nestjs/common';
import * as _ from 'lodash';

@Injectable()
export class ScopeManager {
  private scope: Record<string, unknown> = {};

  /**
   * Get the current scope object.
   */
  getScope(): Record<string, unknown> {
    return this.scope;
  }

  /**
   * Get a single value from the scope using a dot-path key.
   */
  get(key: string): unknown {
    return _.get(this.scope, key);
  }

  /**
   * Merge new fields into the scope.
   */
  merge(fields: Record<string, unknown>): void {
    _.merge(this.scope, fields);
  }

  /**
   * Set a value at a dot-path key inside the scope.
   */
  set(path: string, value: unknown): void {
    _.set(this.scope, path, value);
  }

  /**
   * Check if all provided keys exist inside the scope (non-undefined).
   */
  hasKeys(keys: string[]): boolean {
    return keys.every((key) => _.get(this.scope, key) !== undefined);
  }

  /**
   * Reset the scope (used when creating a fresh execution context).
   */
  reset(): void {
    this.scope = {};
  }

  /**
   * Recursively scan an object/array/string and replace any string
   * value that starts with '$' with its resolved value from the scope.
   * Supports nested paths like $user.name.first
   */
  resolveDynamicValues<T>(payload: T): T {
    if (typeof payload === 'string') {
      return this.resolveString(payload) as unknown as T;
    }

    if (Array.isArray(payload)) {
      return payload.map((item) => this.resolveDynamicValues(item)) as unknown as T;
    }

    if (payload !== null && typeof payload === 'object') {
      const resolved: Record<string, unknown> = {};
      for (const [key, value] of Object.entries(payload as Record<string, unknown>)) {
        resolved[key] = this.resolveDynamicValues(value);
      }
      return resolved as T;
    }

    return payload;
  }

  /**
   * Resolve a single string against the scope.
   * If the string starts with '$', look it up in scope.
   * If not found, return the original string.
   */
  private resolveString(value: string): unknown {
    if (!value.startsWith('$')) return value;

    const path = value.slice(1); // strip leading '$'
    const resolved = _.get(this.scope, path);

    // Return the resolved value, or fall back to original string
    return resolved !== undefined ? resolved : value;
  }

  /**
   * Resolve the `project` output template against the current scope.
   * Returns a clean object with all $ references replaced.
   */
  resolveProject(project: Record<string, unknown>): Record<string, unknown> {
    return this.resolveDynamicValues(project);
  }
}
