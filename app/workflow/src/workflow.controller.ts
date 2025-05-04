import { Controller, Get } from '@nestjs/common';
import { WorkflowService } from './workflow.service';

@Controller('api/workflow')
export class WorkflowController {
  constructor(private readonly workflowService: WorkflowService) {}

  @Get()
  getHello(): string {
    return this.workflowService.getHello();
  }

  @Get('health')
  getHealth(): { status: string } {
    return { status: 'up' };
  }
} 