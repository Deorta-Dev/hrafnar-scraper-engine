import {
  Body,
  Controller,
  Delete,
  HttpCode,
  HttpException,
  HttpStatus,
  Logger,
  Param,
  Post,
} from '@nestjs/common';
import { SessionService } from './session/session.service';
import { ExecuteService } from './execute/execute.service';
import { ExecutePayload, ApiResponse } from './types/instructions.types';

@Controller()
export class AppController {
  private readonly logger = new Logger(AppController.name);

  constructor(
    private readonly sessionService: SessionService,
    private readonly executeService: ExecuteService,
  ) {}

  /**
   * POST /session
   * Create a new isolated browser session.
   */
  @Post('session')
  @HttpCode(200)
  async createSession(): Promise<ApiResponse<{ sessionId: string }>> {
    try {
      const sessionId = await this.sessionService.createSession();
      return { status: 'success', data: { sessionId } };
    } catch (err) {
      this.logger.error(`createSession failed: ${err.message}`);
      throw new HttpException(
        { status: 'error', error: err.message },
        HttpStatus.INTERNAL_SERVER_ERROR,
      );
    }
  }

  /**
   * POST /execute
   * Execute an array of instructions and return the resolved project.
   */
  @Post('execute')
  @HttpCode(200)
  async execute(@Body() payload: ExecutePayload): Promise<ApiResponse> {
    if (!payload?.instructions || !Array.isArray(payload.instructions)) {
      throw new HttpException(
        { status: 'error', error: '`instructions` must be a non-empty array.' },
        HttpStatus.BAD_REQUEST,
      );
    }

    try {
      const result = await this.executeService.execute(payload);
      return {
        status: 'success',
        sessionId: result.sessionId,
        durationMs: result.durationMs,
        data: result.project,
      };
    } catch (err) {
      this.logger.error(`execute failed: ${err.message}`);
      throw new HttpException(
        { status: 'error', error: err.message },
        HttpStatus.INTERNAL_SERVER_ERROR,
      );
    }
  }

  /**
   * DELETE /session/:id
   * Close and destroy a browser session.
   */
  @Delete('session/:id')
  @HttpCode(200)
  async closeSession(
    @Param('id') id: string,
  ): Promise<ApiResponse<{ closed: boolean }>> {
    const closed = await this.sessionService.closeSession(id);
    if (!closed) {
      throw new HttpException(
        { status: 'error', error: `Session ${id} not found.` },
        HttpStatus.NOT_FOUND,
      );
    }
    return { status: 'success', data: { closed } };
  }
}
