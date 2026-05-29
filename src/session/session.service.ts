import {
  Injectable,
  Logger,
  OnModuleDestroy,
  OnModuleInit,
} from '@nestjs/common';
import { chromium, Browser, BrowserContext, Page } from 'playwright-core';
import { v4 as uuidv4 } from 'uuid';

export interface SessionData {
  context: BrowserContext;
  page: Page;
  createdAt: Date;
}

@Injectable()
export class SessionService implements OnModuleInit, OnModuleDestroy {
  private readonly logger = new Logger(SessionService.name);
  private browser: Browser | null = null;
  private sessions: Map<string, SessionData> = new Map();

  async onModuleInit() {
    this.logger.log('Launching Chromium browser...');
    this.browser = await chromium.launch({
      headless: false,
      args: [
        '--no-sandbox',
        '--disable-setuid-sandbox',
        '--disable-dev-shm-usage',
        '--disable-gpu',
      ],
    });
    this.logger.log('Browser ready.');
  }

  async onModuleDestroy() {
    this.logger.log('Closing all sessions and browser...');
    for (const [id] of this.sessions) {
      await this.closeSession(id);
    }
    if (this.browser) {
      await this.browser.close();
    }
  }

  /**
   * Create a new isolated browser context (session).
   * Returns a sessionId (UUID).
   */
  async createSession(): Promise<string> {
    if (!this.browser) throw new Error('Browser not initialized');

    const sessionId = uuidv4();
    const context = await this.browser.newContext({
      userAgent:
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
      viewport: { width: 1280, height: 800 },
      ignoreHTTPSErrors: true,
    });

    const page = await context.newPage();

    this.sessions.set(sessionId, {
      context,
      page,
      createdAt: new Date(),
    });

    this.logger.log(`Session created: ${sessionId}`);
    return sessionId;
  }

  /**
   * Retrieve an existing session by ID.
   */
  getSession(sessionId: string): SessionData | undefined {
    return this.sessions.get(sessionId);
  }

  /**
   * Close and destroy a session by ID.
   */
  async closeSession(sessionId: string): Promise<boolean> {
    const session = this.sessions.get(sessionId);
    if (!session) return false;

    try {
      await session.page.close();
      await session.context.close();
    } catch (e) {
      this.logger.warn(`Error closing session ${sessionId}: ${e.message}`);
    }

    this.sessions.delete(sessionId);
    this.logger.log(`Session closed: ${sessionId}`);
    return true;
  }

  /**
   * Returns true if the given sessionId exists.
   */
  hasSession(sessionId: string): boolean {
    return this.sessions.has(sessionId);
  }

  /**
   * List all active session IDs.
   */
  listSessions(): string[] {
    return Array.from(this.sessions.keys());
  }
}
