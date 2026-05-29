import { Injectable, Logger } from '@nestjs/common';
import { SessionService } from '../session/session.service';
import { ExecutionEngine } from '../engine/execution.engine';
import { ScopeManager } from '../scope/scope.manager';
import { ExecutePayload } from '../types/instructions.types';

export interface ExecuteResult {
  sessionId?: string;
  project: Record<string, unknown>;
  scope: Record<string, unknown>;
  durationMs: number;
}

@Injectable()
export class ExecuteService {
  private readonly logger = new Logger(ExecuteService.name);

  constructor(
    private readonly sessions: SessionService,
    private readonly engine: ExecutionEngine,
  ) {}

  async execute(payload: ExecutePayload): Promise<ExecuteResult> {
    const start = Date.now();

    // ── 1. Session Resolution ──────────────────────────────────
    let sessionId = payload.sessionId;
    let ephemeral = false;

    if (!sessionId || !this.sessions.hasSession(sessionId)) {
      sessionId = await this.sessions.createSession();
      if (!payload.sessionId) {
        ephemeral = true;
        this.logger.debug(`Ephemeral session created: ${sessionId}`);
      }
    }

    const session = this.sessions.getSession(sessionId);
    if (!session) {
      throw new Error(`Session ${sessionId} could not be found.`);
    }

    // ── 2. Scope Initialization ────────────────────────────────
    const scope = new ScopeManager();

    // ── 3. Execute Instructions ────────────────────────────────
    try {
      await this.engine.run(payload.instructions, session.page, scope);
    } catch (err) {
      this.logger.error(`Execution error in session ${sessionId}: ${err.message}`);
      throw err;
    }

    // ── 4. Resolve Project Template ───────────────────────────
    const resolvedProject = payload.project
      ? scope.resolveProject(payload.project)
      : {};

    // ── 5. Session Cleanup ─────────────────────────────────────
    if (ephemeral || payload.closeSession) {
      await this.sessions.closeSession(sessionId);
      sessionId = undefined;
    }

    return {
      sessionId,
      project: resolvedProject,
      scope: scope.getScope(),
      durationMs: Date.now() - start,
    };
  }
}
