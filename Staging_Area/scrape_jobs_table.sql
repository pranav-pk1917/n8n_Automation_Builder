-- Supabase/Postgres Schema for Competitor Intelligence System
-- Run this in your Supabase SQL Editor

-- Create the scrape_jobs table
CREATE TABLE IF NOT EXISTS scrape_jobs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  target_url TEXT NOT NULL,
  status TEXT DEFAULT 'PENDING' CHECK (status IN ('PENDING', 'DISPATCHED', 'COMPLETED', 'ANALYZED', 'FAILED')),
  firecrawl_job_id TEXT,
  scraped_content TEXT,  -- Changed from raw_markdown to match workflow
  result_summary JSONB,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ,
  analyzed_at TIMESTAMPTZ
);

-- If you already have the table with raw_markdown, run this migration instead:
-- ALTER TABLE scrape_jobs RENAME COLUMN raw_markdown TO scraped_content;

-- Create indexes for faster queries
CREATE INDEX IF NOT EXISTS idx_scrape_jobs_status ON scrape_jobs(status);
CREATE INDEX IF NOT EXISTS idx_scrape_jobs_created_at ON scrape_jobs(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_scrape_jobs_target_url ON scrape_jobs(target_url);

-- Enable Row Level Security (optional but recommended)
ALTER TABLE scrape_jobs ENABLE ROW LEVEL SECURITY;

-- Create a policy that allows all operations (adjust based on your security needs)
CREATE POLICY "Allow all operations on scrape_jobs" ON scrape_jobs
  FOR ALL
  USING (true)
  WITH CHECK (true);

-- Grant permissions to the service role
GRANT ALL ON scrape_jobs TO service_role;
GRANT ALL ON scrape_jobs TO authenticated;

-- Add comments for documentation
COMMENT ON TABLE scrape_jobs IS 'Tracks competitor website scraping jobs for the intelligence system';
COMMENT ON COLUMN scrape_jobs.status IS 'Job status: PENDING → DISPATCHED → COMPLETED → ANALYZED (or FAILED)';
COMMENT ON COLUMN scrape_jobs.firecrawl_job_id IS 'The job ID returned by Firecrawl API';
COMMENT ON COLUMN scrape_jobs.raw_markdown IS 'Raw markdown content scraped from the website';
COMMENT ON COLUMN scrape_jobs.result_summary IS 'AI-generated competitive intelligence summary in JSON format';
