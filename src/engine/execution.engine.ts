import { Injectable, Logger } from '@nestjs/common';
import { Page, Response as PlaywrightResponse } from 'playwright-core';
import * as _ from 'lodash';
import { ScopeManager } from '../scope/scope.manager';
import {
  Instruction,
  GotoInstruction,
  ClickInstruction,
  FillInstruction,
  WaitInstruction,
  LabelInstruction,
  JumpInstruction,
  IfInstruction,
  SetInstruction,
  ListenAndTriggerInstruction,
  WaitForListenersInstruction,
  PageFetchInstruction,
  EvaluateInstruction,
  Condition,
  Operator,
} from '../types/instructions.types';

@Injectable()
export class ExecutionEngine {
  private readonly logger = new Logger(ExecutionEngine.name);

  /**
   * Run all instructions against a Playwright Page, using a ScopeManager for state.
   * Uses a while-loop with a mutable pointer to support label/jump/if control flow.
   */
  async run(
    instructions: Instruction[],
    page: Page,
    scope: ScopeManager,
  ): Promise<void> {
    // Pre-build a label index for O(1) jumps
    const labelIndex = this.buildLabelIndex(instructions);

    let pointer = 0;

    while (pointer < instructions.length) {
      const raw = instructions[pointer];

      // Resolve dynamic $variables inside the instruction fields
      const instruction = scope.resolveDynamicValues(raw) as Instruction;

      this.logger.debug(
        `[${pointer}] Executing: ${instruction.type}`,
      );

      let jumped = false;

      switch (instruction.type) {
        case 'goto':
          await this.handleGoto(instruction, page);
          break;

        case 'click':
          await this.handleClick(instruction, page);
          break;

        case 'fill':
          await this.handleFill(instruction, page);
          break;

        case 'wait':
          await this.handleWait(instruction, page);
          break;

        case 'label':
          // Inert marker – do nothing
          break;

        case 'jump': {
          const jumpIdx = this.resolveLabel(
            (instruction as JumpInstruction).to,
            labelIndex,
          );
          pointer = jumpIdx;
          jumped = true;
          break;
        }

        case 'if': {
          const ifInst = instruction as IfInstruction;
          const conditionMet = await this.evaluateCondition(
            ifInst.condition,
            page,
            scope,
          );
          if (conditionMet) {
            const jumpIdx = this.resolveLabel(ifInst.jumpTo, labelIndex);
            pointer = jumpIdx;
            jumped = true;
          }
          break;
        }

        case 'set':
          this.handleSet(instruction as SetInstruction, scope);
          break;

        case 'listenAndTrigger':
          await this.handleListenAndTrigger(
            instruction as ListenAndTriggerInstruction,
            page,
            scope,
          );
          break;

        case 'waitForListeners':
          await this.handleWaitForListeners(
            instruction as WaitForListenersInstruction,
            scope,
          );
          break;

        case 'pageFetch':
          await this.handlePageFetch(
            instruction as PageFetchInstruction,
            page,
            scope,
          );
          break;

        case 'evaluate':
          await this.handleEvaluate(
            instruction as EvaluateInstruction,
            page,
            scope,
          );
          break;

        default:
          this.logger.warn(`Unknown instruction type: ${(instruction as any).type}`);
          break;
      }

      if (!jumped) {
        pointer++;
      }
    }
  }

  // ─────────────────────────────────────────────────────────────
  // Private Handlers
  // ─────────────────────────────────────────────────────────────

  private async handleGoto(inst: GotoInstruction, page: Page): Promise<void> {
    await page.goto(inst.url, {
      waitUntil: inst.waitUntil ?? 'domcontentloaded',
      timeout: 30_000,
    });
  }

  private async handleClick(inst: ClickInstruction, page: Page): Promise<void> {
    if (inst.optional) {
      try {
        await page.click(inst.selector, { timeout: 5_000 });
      } catch {
        this.logger.debug(`Optional click missed: ${inst.selector}`);
      }
    } else {
      await page.click(inst.selector);
    }
  }

  private async handleFill(inst: FillInstruction, page: Page): Promise<void> {
    await page.fill(inst.selector, String(inst.value));
  }

  private async handleWait(inst: WaitInstruction, page: Page): Promise<void> {
    await page.waitForTimeout(inst.time);
  }

  private handleSet(inst: SetInstruction, scope: ScopeManager): void {
    scope.merge(inst.fields);
  }

  private async handleListenAndTrigger(
    inst: ListenAndTriggerInstruction,
    page: Page,
    scope: ScopeManager,
  ): Promise<void> {
    const timeout = inst.timeout ?? 15_000;

    const capturePromise = new Promise<void>((resolve, reject) => {
      const timer = setTimeout(() => {
        page.off('response', handler);
        reject(
          new Error(
            `listenAndTrigger timed out waiting for: ${inst.listen.urlPattern}`,
          ),
        );
      }, timeout);

      const handler = async (response: PlaywrightResponse) => {
        const url = response.url();
        const pattern = inst.listen.urlPattern;

        // Support plain substring match or regex string e.g. "/api\/token/i"
        const matches = this.urlMatches(url, pattern);
        if (!matches) return;

        clearTimeout(timer);
        page.off('response', handler);

        try {
          const json = await response.json();
          const extracted = inst.listen.extractKey
            ? _.get(json, inst.listen.extractKey)
            : json;

          scope.set(inst.saveAs, extracted);
          this.logger.debug(
            `Captured response for "${inst.saveAs}" from ${url}`,
          );
          resolve();
        } catch (e) {
          reject(
            new Error(`Failed to parse response JSON: ${e.message}`),
          );
        }
      };

      page.on('response', handler);
    });

    // Fire trigger AFTER the listener is registered to avoid race conditions
    if (inst.trigger.type === 'click') {
      await page.click(inst.trigger.selector);
    }

    await capturePromise;
  }

  private async handleWaitForListeners(
    inst: WaitForListenersInstruction,
    scope: ScopeManager,
  ): Promise<void> {
    const timeout = inst.timeout ?? 15_000;
    const pollInterval = inst.pollInterval ?? 200;
    const deadline = Date.now() + timeout;

    while (Date.now() < deadline) {
      if (scope.hasKeys(inst.keys)) return;
      await sleep(pollInterval);
    }

    const missing = inst.keys.filter(
      (k) => scope.get(k) === undefined,
    );
    throw new Error(
      `waitForListeners timed out. Missing keys: ${missing.join(', ')}`,
    );
  }

  private async handlePageFetch(
    inst: PageFetchInstruction,
    page: Page,
    scope: ScopeManager,
  ): Promise<void> {
    const result = await page.evaluate(
      async ({ url, options }) => {
        const res = await fetch(url, options);
        const contentType = res.headers.get('content-type') ?? '';
        if (contentType.includes('application/json')) {
          return res.json();
        }
        return res.text();
      },
      { url: inst.url, options: inst.options ?? {} },
    );

    scope.set(inst.saveAs, result);
  }

  private async handleEvaluate(
    inst: EvaluateInstruction,
    page: Page,
    scope: ScopeManager,
  ): Promise<void> {
    // eslint-disable-next-line @typescript-eslint/no-implied-eval
    const fn = new Function(`return (${inst.script})`)() as (...args: unknown[]) => unknown;
    const result = await page.evaluate(fn, ...(inst.args ?? []));

    if (inst.saveAs) {
      scope.set(inst.saveAs, result);
    }
  }

  // ─────────────────────────────────────────────────────────────
  // Condition Evaluators
  // ─────────────────────────────────────────────────────────────

  private async evaluateCondition(
    condition: Condition,
    page: Page,
    scope: ScopeManager,
  ): Promise<boolean> {
    if (condition.type === 'elementExists') {
      const count = await page.locator(condition.selector).count();
      return count > 0;
    }

    if (condition.type === 'scopeEvaluate') {
      const left = this.resolveOperand(condition.left, scope);
      const right = this.resolveOperand(condition.right, scope);
      return this.compare(left, right, condition.operator);
    }

    return false;
  }

  private resolveOperand(
    value: string | number | boolean,
    scope: ScopeManager,
  ): unknown {
    if (typeof value === 'string' && value.startsWith('$')) {
      return scope.get(value.slice(1));
    }
    return value;
  }

  private compare(left: unknown, right: unknown, operator: Operator): boolean {
    switch (operator) {
      case '===': return left === right;
      case '!==': return left !== right;
      case '>':   return (left as number) > (right as number);
      case '<':   return (left as number) < (right as number);
      case '>=':  return (left as number) >= (right as number);
      case '<=':  return (left as number) <= (right as number);
      default:    return false;
    }
  }

  // ─────────────────────────────────────────────────────────────
  // Label / Jump Helpers
  // ─────────────────────────────────────────────────────────────

  private buildLabelIndex(instructions: Instruction[]): Map<string, number> {
    const index = new Map<string, number>();
    instructions.forEach((inst, i) => {
      if (inst.type === 'label') {
        index.set((inst as LabelInstruction).name, i);
      }
    });
    return index;
  }

  private resolveLabel(
    labelName: string,
    labelIndex: Map<string, number>,
  ): number {
    const idx = labelIndex.get(labelName);
    if (idx === undefined) {
      throw new Error(`Label not found: "${labelName}"`);
    }
    return idx;
  }

  // ─────────────────────────────────────────────────────────────
  // URL Pattern Matching
  // ─────────────────────────────────────────────────────────────

  private urlMatches(url: string, pattern: string): boolean {
    // Detect regex format: /pattern/flags
    const regexMatch = pattern.match(/^\/(.+)\/([gimsuy]*)$/);
    if (regexMatch) {
      const [, body, flags] = regexMatch;
      return new RegExp(body, flags).test(url);
    }
    return url.includes(pattern);
  }
}

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}
