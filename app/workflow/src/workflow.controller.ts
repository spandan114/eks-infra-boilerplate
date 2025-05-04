import { Controller, Get } from '@nestjs/common';
import { WorkflowService } from './workflow.service';

@Controller('workflow')
export class WorkflowController {
  constructor(private readonly workflowService: WorkflowService) {}

  @Get()
  getHello(): string {
    return this.workflowService.getHello();
  }
} 