-- =============================================================================
-- Dev seed: two dummy clients to validate multi-tenancy.
-- DO NOT run in production. This file is for local/dev/staging only.
--
-- Client 1: Webley Media (matches the Vercel site's 4 service pillars).
-- Client 2: Acme Threads (hypothetical clothing DTC brand) - totally different
--           pillars to prove the system isn't Webley-shaped.
-- =============================================================================

begin;

-- ---------------------------------------------------------------------------
-- Client 1: Webley Media
-- ---------------------------------------------------------------------------

insert into clients (id, name, slug, canonical_domain, config, onboarding_status) values
(
    '11111111-1111-1111-1111-111111111111',
    'Webley Media',
    'webley-media',
    'webleymedia.com',
    jsonb_build_object(
        'service_pillars', jsonb_build_array(
            jsonb_build_object('name', 'visibility',     'url_path', '/services/visibility',     'description', 'SEO + content + GEO + organic social + PR + brand awareness'),
            jsonb_build_object('name', 'performance',    'url_path', '/services/performance',    'description', 'Paid acquisition (Google, Meta, LinkedIn, TikTok) + CRO + attribution + performance creative'),
            jsonb_build_object('name', 'creative',       'url_path', '/services/creative',       'description', 'Brand design + video + copywriting + photography + motion + creative strategy'),
            jsonb_build_object('name', 'infrastructure', 'url_path', '/services/infrastructure', 'description', 'Web dev + app dev + marketing tech stack (HubSpot, Klaviyo, Segment) + CRM + automation + headless CMS')
        ),
        'icp_persona', 'Founders / CMOs / Heads of Marketing at $1M-50M ARR B2B companies in healthcare, pharma, fintech, B2B SaaS, and DTC e-commerce. Looking for full-stack digital marketing partnership rather than freelancers or DIY tools. Decision authority over $5k-50k/mo retainer.',
        'brand_voice', 'Confident, evidence-based, sparring-partner tone. Numbers over adjectives. Calls out industry BS where appropriate. Not corporate, not bro-y.',
        'tone_examples', jsonb_build_array(
            'Most agencies pitch ''we drive results.'' We pitch the audit that proves whether they actually do.',
            'Conversion rate is a vanity metric. Pipeline-weighted CAC is the metric.'
        ),
        'monthly_api_budget_usd',          50,
        'expected_runs_per_month',         4,
        'per_run_cost_ceiling_pct',        150,
        'review_tier',                     'tier_b_hitl_borderline',
        'navigational_competitor_strategy','allow_comparison_only',
        'hitl_channels',                   jsonb_build_array('slack'),
        'hitl_routing', jsonb_build_object(
            'borderline',            'slack',
            'high_severity',         jsonb_build_array('slack'),
            'taxonomy_suggestions',  'slack',
            'cost_ceiling',          jsonb_build_array('slack'),
            'quality_drift',         jsonb_build_array('slack'),
            'onboarding_review',     'slack'
        ),
        'negative_overrides', jsonb_build_array(),
        'positive_overrides', jsonb_build_array()
    ),
    'active'
);

-- Webley niches (starter list; will extend via taxonomy_suggestions as data reveals more)
insert into niches (client_id, name, description, source) values
('11111111-1111-1111-1111-111111111111', 'healthcare',    'Healthcare providers, clinics, hospitals, telemedicine',                    'onboarding_declared'),
('11111111-1111-1111-1111-111111111111', 'pharmaceuticals','Pharma manufacturers and biotech',                                          'onboarding_declared'),
('11111111-1111-1111-1111-111111111111', 'fintech',       'Banking, payments, lending, investment platforms',                          'onboarding_declared'),
('11111111-1111-1111-1111-111111111111', 'b2b_saas',      'B2B software companies',                                                    'onboarding_declared'),
('11111111-1111-1111-1111-111111111111', 'ecommerce_dtc', 'Direct-to-consumer e-commerce brands',                                      'onboarding_declared'),
('11111111-1111-1111-1111-111111111111', 'professional_services','Law firms, accounting, consulting, agencies',                       'onboarding_declared');

-- Starter negative terms (port of common rules from rebuild_negative_v2.ps1)
insert into negative_terms (client_id, term, match_type) values
('11111111-1111-1111-1111-111111111111', 'free',           'contains'),
('11111111-1111-1111-1111-111111111111', 'how to',         'contains'),
('11111111-1111-1111-1111-111111111111', 'tutorial',       'contains'),
('11111111-1111-1111-1111-111111111111', 'diy',            'contains'),
('11111111-1111-1111-1111-111111111111', 'do it yourself', 'contains'),
('11111111-1111-1111-1111-111111111111', 'youtube',        'contains'),
('11111111-1111-1111-1111-111111111111', 'reddit',         'contains'),
('11111111-1111-1111-1111-111111111111', 'salary',         'contains'),
('11111111-1111-1111-1111-111111111111', 'jobs',           'contains'),
('11111111-1111-1111-1111-111111111111', 'internship',     'contains'),
('11111111-1111-1111-1111-111111111111', 'course',         'contains'),
('11111111-1111-1111-1111-111111111111', 'wikipedia',      'contains'),
('11111111-1111-1111-1111-111111111111', 'pdf',            'contains'),
('11111111-1111-1111-1111-111111111111', 'download',       'contains');

-- Starter positive terms
insert into positive_terms (client_id, term, match_type) values
('11111111-1111-1111-1111-111111111111', 'agency',           'contains'),
('11111111-1111-1111-1111-111111111111', 'consulting',       'contains'),
('11111111-1111-1111-1111-111111111111', 'firm',             'contains'),
('11111111-1111-1111-1111-111111111111', 'services',         'contains'),
('11111111-1111-1111-1111-111111111111', 'company',          'contains'),
('11111111-1111-1111-1111-111111111111', 'partner',          'contains'),
('11111111-1111-1111-1111-111111111111', 'cost',             'contains'),
('11111111-1111-1111-1111-111111111111', 'pricing',          'contains'),
('11111111-1111-1111-1111-111111111111', 'hire',             'contains'),
('11111111-1111-1111-1111-111111111111', 'enterprise',       'contains');

-- Static pages for Webley's Vercel site (will be re-synced by WF-00; this is just bootstrap)
insert into pages (client_id, url_path, title, source, service_pillar, intent_type) values
('11111111-1111-1111-1111-111111111111', '/',                          'Webley Media - Digital Marketing',     'next_static', null,             'navigational_branded'),
('11111111-1111-1111-1111-111111111111', '/about',                     'About Webley Media',                   'next_static', null,             'navigational_branded'),
('11111111-1111-1111-1111-111111111111', '/services',                  'Our Services',                         'next_static', null,             'commercial_investigation'),
('11111111-1111-1111-1111-111111111111', '/services/visibility',       'Visibility - SEO + Content + GEO',     'next_static', 'visibility',     'commercial_investigation'),
('11111111-1111-1111-1111-111111111111', '/services/performance',      'Performance - Paid + CRO',             'next_static', 'performance',    'commercial_investigation'),
('11111111-1111-1111-1111-111111111111', '/services/creative',         'Creative - Design + Video',            'next_static', 'creative',       'commercial_investigation'),
('11111111-1111-1111-1111-111111111111', '/services/infrastructure',   'Infrastructure - Web + App + Tech',    'next_static', 'infrastructure', 'commercial_investigation'),
('11111111-1111-1111-1111-111111111111', '/case-studies',              'Case Studies',                         'next_static', null,             'commercial_investigation'),
('11111111-1111-1111-1111-111111111111', '/process',                   'Our Process',                          'next_static', null,             'informational'),
('11111111-1111-1111-1111-111111111111', '/blog',                      'Blog',                                 'next_static', null,             'informational'),
('11111111-1111-1111-1111-111111111111', '/contact',                   'Contact Us',                           'next_static', null,             'transactional'),
('11111111-1111-1111-1111-111111111111', '/careers',                   'Careers',                              'next_static', null,             'navigational_other');

-- ---------------------------------------------------------------------------
-- Client 2: Acme Threads (hypothetical clothing DTC brand)
-- Different pillars, different niches, different ICP - proves the system is
-- not Webley-shaped.
-- ---------------------------------------------------------------------------

insert into clients (id, name, slug, canonical_domain, config, onboarding_status) values
(
    '22222222-2222-2222-2222-222222222222',
    'Acme Threads',
    'acme-threads',
    'acmethreads.example',
    jsonb_build_object(
        'service_pillars', jsonb_build_array(
            jsonb_build_object('name', 'mens',       'url_path', '/men',       'description', 'Mens apparel collection'),
            jsonb_build_object('name', 'womens',     'url_path', '/women',     'description', 'Womens apparel collection'),
            jsonb_build_object('name', 'accessories','url_path', '/accessories','description', 'Bags, belts, hats, scarves'),
            jsonb_build_object('name', 'sale',       'url_path', '/sale',      'description', 'Discounted items')
        ),
        'icp_persona', 'Direct consumer aged 25-40 with disposable income $80k+/yr, fashion-conscious, sustainability-aware, shops online primarily on mobile. Looking for premium-but-attainable wardrobe staples.',
        'brand_voice', 'Warm, confident, design-forward. Like a stylish friend recommending something they love.',
        'monthly_api_budget_usd',          30,
        'expected_runs_per_month',         2,
        'per_run_cost_ceiling_pct',        150,
        'review_tier',                     'tier_a_ai_only',
        'navigational_competitor_strategy','reject_all',
        'hitl_channels',                   jsonb_build_array('telegram'),
        'hitl_routing', jsonb_build_object(
            'borderline',            'telegram',
            'high_severity',         jsonb_build_array('telegram'),
            'taxonomy_suggestions',  'telegram',
            'cost_ceiling',          jsonb_build_array('telegram'),
            'quality_drift',         jsonb_build_array('telegram'),
            'onboarding_review',     'telegram'
        ),
        'negative_overrides', jsonb_build_array(),
        'positive_overrides', jsonb_build_array()
    ),
    'active'
);

insert into niches (client_id, name, source) values
('22222222-2222-2222-2222-222222222222', 'sustainable_fashion',  'onboarding_declared'),
('22222222-2222-2222-2222-222222222222', 'workwear',             'onboarding_declared'),
('22222222-2222-2222-2222-222222222222', 'athleisure',           'onboarding_declared');

commit;
