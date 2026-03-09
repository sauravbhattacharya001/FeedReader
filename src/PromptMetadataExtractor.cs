namespace Prompt
{
    using System;
    using System.Collections.Generic;
    using System.Linq;
    using System.Text.RegularExpressions;

    /// <summary>
    /// Detected capability that a prompt requires from the LLM.
    /// </summary>
    public enum PromptCapability
    {
        /// <summary>General text generation.</summary>
        TextGeneration,
        /// <summary>Source code generation or analysis.</summary>
        CodeGeneration,
        /// <summary>Mathematical computation or reasoning.</summary>
        MathReasoning,
        /// <summary>Image understanding or generation.</summary>
        VisionOrImage,
        /// <summary>Web search or real-time information.</summary>
        WebSearch,
        /// <summary>File or document processing.</summary>
        DocumentProcessing,
        /// <summary>Data analysis, statistics, or charting.</summary>
        DataAnalysis,
        /// <summary>Translation between languages.</summary>
        Translation,
        /// <summary>Summarization of long content.</summary>
        Summarization,
        /// <summary>Structured output (JSON, XML, CSV).</summary>
        StructuredOutput,
        /// <summary>Multi-turn reasoning or chain-of-thought.</summary>
        Reasoning,
        /// <summary>Tool or function calling.</summary>
        ToolUse
    }

    /// <summary>
    /// Detected domain/subject area of a prompt.
    /// </summary>
    public enum PromptDomain
    {
        /// <summary>General or unclassified.</summary>
        General,
        /// <summary>Software engineering and programming.</summary>
        Technology,
        /// <summary>Medical or healthcare related.</summary>
        Medical,
        /// <summary>Legal documents or questions.</summary>
        Legal,
        /// <summary>Financial analysis, trading, accounting.</summary>
        Finance,
        /// <summary>Academic research or education.</summary>
        Academic,
        /// <summary>Marketing, advertising, copywriting.</summary>
        Marketing,
        /// <summary>Creative writing, fiction, poetry.</summary>
        Creative,
        /// <summary>Science and engineering.</summary>
        Science,
        /// <summary>Business operations and management.</summary>
        Business
    }

    /// <summary>
    /// Detected tone/formality level of a prompt.
    /// </summary>
    public enum PromptTone
    {
        /// <summary>Very formal (legal, academic).</summary>
        Formal,
        /// <summary>Professional but approachable.</summary>
        Professional,
        /// <summary>Neutral — neither formal nor casual.</summary>
        Neutral,
        /// <summary>Casual and conversational.</summary>
        Casual,
        /// <summary>Very informal, slang-heavy.</summary>
        Informal
    }

    /// <summary>
    /// Detected language/locale of a prompt.
    /// </summary>
    public class DetectedLanguage
    {
        /// <summary>Gets the ISO 639-1 language code (e.g., "en", "es", "zh").</summary>
        public string Code { get; internal set; } = "en";

        /// <summary>Gets the language name.</summary>
        public string Name { get; internal set; } = "English";

        /// <summary>Gets the confidence score (0.0-1.0).</summary>
        public double Confidence { get; internal set; } = 1.0;
    }

    /// <summary>
    /// A named entity extracted from a prompt.
    /// </summary>
    public class ExtractedEntity
    {
        /// <summary>Gets the entity text as found in the prompt.</summary>
        public string Text { get; internal set; } = "";

        /// <summary>Gets the entity type (e.g., "email", "url", "date", "number", "code_lang", "file_path").</summary>
        public string Type { get; internal set; } = "";

        /// <summary>Gets the character position where the entity starts.</summary>
        public int StartIndex { get; internal set; }
    }

    /// <summary>
    /// Full metadata extraction result for a prompt.
    /// </summary>
    public class PromptMetadata
    {
        /// <summary>Gets the detected primary language.</summary>
        public DetectedLanguage Language { get; internal set; } = new();

        /// <summary>Gets detected capabilities required by this prompt.</summary>
        public List<PromptCapability> Capabilities { get; internal set; } = new();

        /// <summary>Gets the detected domain/subject area.</summary>
        public PromptDomain Domain { get; internal set; } = PromptDomain.General;

        /// <summary>Gets the domain confidence score (0.0-1.0).</summary>
        public double DomainConfidence { get; internal set; }

        /// <summary>Gets the detected tone/formality.</summary>
        public PromptTone Tone { get; internal set; } = PromptTone.Neutral;

        /// <summary>Gets named entities extracted from the prompt.</summary>
        public List<ExtractedEntity> Entities { get; internal set; } = new();

        /// <summary>Gets the word count.</summary>
        public int WordCount { get; internal set; }

        /// <summary>Gets the estimated token count (word-based approximation).</summary>
        public int EstimatedTokens { get; internal set; }

        /// <summary>Gets the count of questions detected.</summary>
        public int QuestionCount { get; internal set; }

        /// <summary>Gets the count of explicit instructions/commands detected.</summary>
        public int InstructionCount { get; internal set; }

        /// <summary>Gets whether the prompt contains examples (few-shot).</summary>
        public bool HasExamples { get; internal set; }

        /// <summary>Gets whether the prompt contains system-level directives.</summary>
        public bool HasSystemDirectives { get; internal set; }

        /// <summary>Gets a routing suggestion string (e.g., "fast", "standard", "premium", "specialist").</summary>
        public string RoutingSuggestion { get; internal set; } = "standard";

        /// <summary>Gets additional key-value metadata tags.</summary>
        public Dictionary<string, string> Tags { get; internal set; } = new();
    }

    /// <summary>
    /// Extracts structured metadata from prompt text: language detection, capability
    /// requirements, domain classification, tone analysis, entity extraction, and
    /// routing suggestions.
    /// </summary>
    /// <remarks>
    /// <para>
    /// Example usage:
    /// <code>
    /// var extractor = new PromptMetadataExtractor();
    /// var metadata = extractor.Extract("Write a Python function that calculates compound interest");
    ///
    /// Console.WriteLine($"Domain: {metadata.Domain}");           // Technology
    /// Console.WriteLine($"Capabilities: {string.Join(", ", metadata.Capabilities)}"); // CodeGeneration, MathReasoning
    /// Console.WriteLine($"Tone: {metadata.Tone}");               // Neutral
    /// Console.WriteLine($"Route: {metadata.RoutingSuggestion}"); // standard
    /// </code>
    /// </para>
    /// </remarks>
    public class PromptMetadataExtractor
    {
        // ── Compiled regex patterns with ReDoS-safe timeouts ──────────

        private static readonly Regex EmailPattern = new(
            @"\b[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}\b",
            RegexOptions.Compiled, TimeSpan.FromMilliseconds(500));

        private static readonly Regex UrlPattern = new(
            @"https?://[^\s<>""']+",
            RegexOptions.Compiled, TimeSpan.FromMilliseconds(500));

        private static readonly Regex FilePathPattern = new(
            @"(?:[A-Za-z]:\\[\w\\.\-]+|/(?:[\w.\-]+/)+[\w.\-]+|\b[\w\-]+\.(?:py|js|ts|cs|java|cpp|rb|go|rs|swift|kt|dart|html|css|json|xml|yaml|yml|md|txt|csv|sql|sh|ps1))\b",
            RegexOptions.Compiled, TimeSpan.FromMilliseconds(500));

        private static readonly Regex DatePattern = new(
            @"\b\d{4}[-/]\d{1,2}[-/]\d{1,2}\b|\b(?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)\w*\s+\d{1,2},?\s*\d{4}\b",
            RegexOptions.IgnoreCase | RegexOptions.Compiled, TimeSpan.FromMilliseconds(500));

        private static readonly Regex NumberPattern = new(
            @"\b\d{1,3}(?:,\d{3})*(?:\.\d+)?%?\b|\$\d+(?:,\d{3})*(?:\.\d+)?",
            RegexOptions.Compiled, TimeSpan.FromMilliseconds(500));

        private static readonly Regex QuestionPattern = new(
            @"[?\uff1f]\s*$",
            RegexOptions.Multiline | RegexOptions.Compiled, TimeSpan.FromMilliseconds(500));

        private static readonly Regex InstructionPattern = new(
            @"^\s*(?:\d+[.\)]\s+|[-*]\s+)?(?:write|create|generate|build|implement|design|explain|analyze|calculate|convert|translate|summarize|list|describe|compare|fix|debug|refactor|optimize|review|check|validate|test|format|parse|extract|find|search|classify|categorize|sort|filter|merge|split|combine|add|remove|update|modify|delete|insert)\b",
            RegexOptions.IgnoreCase | RegexOptions.Multiline | RegexOptions.Compiled, TimeSpan.FromMilliseconds(500));

        private static readonly Regex CodeBlockPattern = new(
            @"```[\s\S]*?```|`[^`\n]+`",
            RegexOptions.Compiled, TimeSpan.FromMilliseconds(500));

        private static readonly Regex ExamplePattern = new(
            @"\b(?:for example|e\.g\.|example:|input:|output:|sample:|given:|expected:)\b",
            RegexOptions.IgnoreCase | RegexOptions.Compiled, TimeSpan.FromMilliseconds(500));

        private static readonly Regex SystemDirectivePattern = new(
            @"\b(?:you are|act as|behave as|your role|system:|instructions:|rules:|constraints:|you must|you should|always|never)\b",
            RegexOptions.IgnoreCase | RegexOptions.Compiled, TimeSpan.FromMilliseconds(500));

        private static readonly Regex JsonStructurePattern = new(
            @"\{[\s\S]*?:[\s\S]*?\}|\[[\s\S]*?\]|(?:json|xml|csv|yaml)\s*(?:format|output|schema|response)",
            RegexOptions.IgnoreCase | RegexOptions.Compiled, TimeSpan.FromMilliseconds(500));

        // ── Language detection word sets ──────────────────────────────

        private static readonly Dictionary<string, (string Name, string[] Markers)> LanguageMarkers = new()
        {
            ["es"] = ("Spanish", new[] { " el ", " la ", " los ", " las ", " de ", " en ", " por ", " para ", " que ", " del ", " con ", " una ", " como " }),
            ["fr"] = ("French", new[] { " le ", " la ", " les ", " des ", " est ", " une ", " dans ", " pour ", " que ", " avec ", " sur ", " pas ", " sont " }),
            ["de"] = ("German", new[] { " der ", " die ", " das ", " ist ", " ein ", " eine ", " und ", " nicht ", " mit ", " auf ", " den ", " sich " }),
            ["pt"] = ("Portuguese", new[] { " de ", " que ", " em ", " para ", " com ", " uma ", " por ", " mais ", " como ", " seu ", " essa ", " isso " }),
            ["it"] = ("Italian", new[] { " il ", " di ", " che ", " la ", " per ", " una ", " del ", " con ", " sono ", " alla ", " della ", " nel " }),
            ["zh"] = ("Chinese", new[] { "\u7684", "\u662f", "\u4e86", "\u5728", "\u6709", "\u548c", "\u4eba", "\u8fd9", "\u4e2d", "\u4e0d" }),
            ["ja"] = ("Japanese", new[] { "\u306e", "\u306f", "\u3092", "\u306b", "\u304c", "\u3067", "\u3068", "\u305f", "\u3059\u308b", "\u3067\u3059" }),
            ["ko"] = ("Korean", new[] { "\uc740", "\ub294", "\uc774", "\uac00", "\ub97c", "\uc744", "\uc5d0", "\uc758", "\ub85c", "\ud558\ub2e4" }),
            ["ru"] = ("Russian", new[] { " \u0438 ", " \u0432 ", " \u043d\u0435 ", " \u043d\u0430 ", " \u0447\u0442\u043e ", " \u043e\u043d ", " \u043a\u0430\u043a ", " \u044d\u0442\u043e ", " \u0434\u043b\u044f ", " \u043f\u043e " }),
            ["ar"] = ("Arabic", new[] { "\u0641\u064a", "\u0645\u0646", "\u0639\u0644\u0649", "\u0625\u0644\u0649", "\u0647\u0630\u0627", "\u0623\u0646", "\u0627\u0644\u062a\u064a", "\u0627\u0644\u062a\u0649" }),
            ["hi"] = ("Hindi", new[] { "\u0939\u0948", "\u0915\u0947", "\u092e\u0947\u0902", "\u0915\u093e", "\u0915\u0940", "\u0915\u094b", "\u0914\u0930", "\u0938\u0947", "\u0939\u0948\u0902", "\u092a\u0930" }),
        };

        // ── Domain keyword sets ──────────────────────────────────────

        private static readonly Dictionary<PromptDomain, string[]> DomainKeywords = new()
        {
            [PromptDomain.Technology] = new[] {
                "code", "function", "api", "database", "sql", "algorithm", "debug", "compile",
                "deploy", "git", "docker", "kubernetes", "python", "javascript", "typescript",
                "java", "csharp", "c#", "rust", "golang", "react", "angular", "vue",
                "html", "css", "server", "client", "frontend", "backend", "microservice",
                "rest", "graphql", "cicd", "devops", "cloud", "aws", "azure", "linux",
                "refactor", "bug", "error", "exception", "class", "interface", "method"
            },
            [PromptDomain.Medical] = new[] {
                "patient", "diagnosis", "symptom", "treatment", "medication", "dosage",
                "clinical", "pathology", "surgery", "therapy", "prescription", "vaccine",
                "anatomy", "disease", "chronic", "acute", "prognosis", "epidemiology",
                "radiology", "oncology", "cardiology", "neurology", "pediatric"
            },
            [PromptDomain.Legal] = new[] {
                "contract", "clause", "statute", "jurisdiction", "plaintiff", "defendant",
                "litigation", "arbitration", "compliance", "regulation", "tort", "liability",
                "precedent", "court", "judge", "attorney", "counsel", "intellectual property",
                "patent", "trademark", "copyright", "indemnify", "fiduciary"
            },
            [PromptDomain.Finance] = new[] {
                "revenue", "profit", "investment", "portfolio", "stock", "bond", "dividend",
                "interest rate", "inflation", "gdp", "balance sheet", "cash flow", "equity",
                "hedge", "derivative", "ipo", "valuation", "roi", "ebitda", "amortization",
                "depreciation", "fiscal", "monetary", "compound interest"
            },
            [PromptDomain.Academic] = new[] {
                "thesis", "dissertation", "peer review", "citation", "bibliography",
                "hypothesis", "methodology", "literature review", "abstract", "journal",
                "conference paper", "empirical", "qualitative", "quantitative", "curriculum",
                "syllabus", "lecture", "semester", "academic", "research paper"
            },
            [PromptDomain.Marketing] = new[] {
                "campaign", "brand", "audience", "conversion", "engagement", "seo",
                "content marketing", "social media", "influencer", "funnel", "cta",
                "landing page", "a/b test", "click-through", "impression", "reach",
                "copywriting", "tagline", "slogan", "demographics", "segmentation"
            },
            [PromptDomain.Creative] = new[] {
                "story", "poem", "novel", "character", "plot", "dialogue", "narrative",
                "fiction", "creative writing", "screenplay", "lyric", "metaphor",
                "protagonist", "antagonist", "setting", "worldbuilding", "genre"
            },
            [PromptDomain.Science] = new[] {
                "experiment", "hypothesis", "molecule", "atom", "quantum", "gravity",
                "thermodynamics", "evolution", "genome", "cell", "photosynthesis",
                "chemical reaction", "physics", "biology", "chemistry", "ecology",
                "geology", "astronomy", "particle", "wavelength", "electromagnetic"
            },
            [PromptDomain.Business] = new[] {
                "strategy", "stakeholder", "kpi", "roadmap", "quarterly", "vendor",
                "procurement", "supply chain", "logistics", "operations", "hr",
                "onboarding", "retention", "churn", "meeting agenda", "proposal",
                "invoice", "milestone", "deliverable", "scope", "budget planning"
            },
        };

        // ── Capability keyword sets ──────────────────────────────────

        private static readonly Dictionary<PromptCapability, string[]> CapabilityKeywords = new()
        {
            [PromptCapability.CodeGeneration] = new[] {
                "code", "function", "class", "method", "implement", "program", "script",
                "debug", "compile", "refactor", "algorithm", "syntax", "api", "sdk",
                "library", "framework", "unittest", "test case"
            },
            [PromptCapability.MathReasoning] = new[] {
                "calculate", "equation", "formula", "derivative", "integral", "probability",
                "statistics", "algebra", "geometry", "matrix", "polynomial", "logarithm",
                "factorial", "permutation", "combination", "arithmetic", "solve"
            },
            [PromptCapability.VisionOrImage] = new[] {
                "image", "photo", "picture", "screenshot", "diagram", "chart", "graph",
                "visual", "draw", "illustrate", "render", "pixel", "resolution"
            },
            [PromptCapability.WebSearch] = new[] {
                "search", "latest", "current", "recent", "today", "news", "update",
                "real-time", "live", "trending", "as of"
            },
            [PromptCapability.DocumentProcessing] = new[] {
                "document", "pdf", "file", "upload", "attachment", "spreadsheet", "docx",
                "parse file", "read file", "extract from"
            },
            [PromptCapability.DataAnalysis] = new[] {
                "analyze data", "dataset", "correlat", "regression", "outlier", "trend",
                "visualization", "histogram", "scatter plot", "pivot", "aggregate",
                "mean", "median", "standard deviation", "percentile"
            },
            [PromptCapability.Translation] = new[] {
                "translate", "translation", "localize", "in english", "in spanish",
                "in french", "in german", "in chinese", "in japanese", "multilingual"
            },
            [PromptCapability.Summarization] = new[] {
                "summarize", "summary", "condense", "brief", "tldr", "key points",
                "main ideas", "overview", "recap", "digest"
            },
            [PromptCapability.StructuredOutput] = new[] {
                "json", "xml", "csv", "yaml", "table", "schema", "structured",
                "formatted output", "markdown table"
            },
            [PromptCapability.Reasoning] = new[] {
                "step by step", "think through", "reason", "chain of thought",
                "logical", "deduce", "infer", "conclude", "prove", "compare and contrast",
                "pros and cons", "evaluate", "critique"
            },
            [PromptCapability.ToolUse] = new[] {
                "call", "invoke", "tool", "function call", "api call", "execute",
                "run command", "plugin", "action"
            },
        };

        /// <summary>
        /// Extracts comprehensive metadata from a prompt string.
        /// </summary>
        /// <param name="prompt">The prompt text to analyze.</param>
        /// <returns>A <see cref="PromptMetadata"/> with all detected metadata.</returns>
        /// <exception cref="ArgumentNullException">Thrown when prompt is null.</exception>
        public PromptMetadata Extract(string prompt)
        {
            if (prompt == null) throw new ArgumentNullException(nameof(prompt));

            var metadata = new PromptMetadata();
            var text = prompt.Trim();

            if (text.Length == 0) return metadata;

            // Basic counts
            var words = text.Split(new[] { ' ', '\t', '\n', '\r' }, StringSplitOptions.RemoveEmptyEntries);
            metadata.WordCount = words.Length;
            metadata.EstimatedTokens = EstimateTokens(text);

            // Language detection
            metadata.Language = DetectLanguage(text);

            // Questions and instructions
            metadata.QuestionCount = CountMatches(QuestionPattern, text);
            metadata.InstructionCount = CountMatches(InstructionPattern, text);

            // Examples and system directives
            metadata.HasExamples = ExamplePattern.IsMatch(text) || CodeBlockPattern.IsMatch(text);
            metadata.HasSystemDirectives = SystemDirectivePattern.IsMatch(text);

            // Entity extraction
            metadata.Entities = ExtractEntities(text);

            // Capability detection
            metadata.Capabilities = DetectCapabilities(text);

            // Domain classification
            var (domain, confidence) = ClassifyDomain(text);
            metadata.Domain = domain;
            metadata.DomainConfidence = confidence;

            // Tone analysis
            metadata.Tone = AnalyzeTone(text);

            // Routing suggestion
            metadata.RoutingSuggestion = SuggestRouting(metadata);

            // Tags
            metadata.Tags = BuildTags(metadata, text);

            return metadata;
        }

        /// <summary>
        /// Extracts metadata from multiple prompts and returns results.
        /// </summary>
        /// <param name="prompts">The prompt texts to analyze.</param>
        /// <returns>A list of <see cref="PromptMetadata"/> results.</returns>
        public List<PromptMetadata> ExtractBatch(IEnumerable<string> prompts)
        {
            if (prompts == null) throw new ArgumentNullException(nameof(prompts));
            return prompts.Select(Extract).ToList();
        }

        // ── Private methods ──────────────────────────────────────────

        private static int EstimateTokens(string text)
        {
            // GPT-style approximation: ~0.75 words per token for English,
            // ~1.5 chars per token for CJK
            var asciiWords = text.Split(new[] { ' ', '\t', '\n', '\r' }, StringSplitOptions.RemoveEmptyEntries).Length;
            var cjkChars = text.Count(c => c >= 0x4E00 && c <= 0x9FFF ||
                                           c >= 0x3040 && c <= 0x309F ||
                                           c >= 0x30A0 && c <= 0x30FF ||
                                           c >= 0xAC00 && c <= 0xD7AF);
            return (int)(asciiWords / 0.75) + (int)(cjkChars / 1.5);
        }

        private static DetectedLanguage DetectLanguage(string text)
        {
            var padded = " " + text.ToLowerInvariant() + " ";
            var bestCode = "en";
            var bestName = "English";
            var bestScore = 0;

            foreach (var (code, (name, markers)) in LanguageMarkers)
            {
                var hits = markers.Count(m => padded.Contains(m));
                if (hits > bestScore)
                {
                    bestScore = hits;
                    bestCode = code;
                    bestName = name;
                }
            }

            // English is the default; only override if strong signal
            var englishMarkers = new[] { " the ", " is ", " are ", " was ", " have ", " has ", " will ", " would ", " can ", " this ", " that ", " with ", " from " };
            var englishHits = englishMarkers.Count(m => padded.Contains(m));

            if (bestScore > englishHits && bestScore >= 3)
            {
                return new DetectedLanguage
                {
                    Code = bestCode,
                    Name = bestName,
                    Confidence = Math.Min(1.0, bestScore / 8.0)
                };
            }

            return new DetectedLanguage
            {
                Code = "en",
                Name = "English",
                Confidence = englishHits >= 3 ? Math.Min(1.0, englishHits / 8.0) : 0.5
            };
        }

        private static List<ExtractedEntity> ExtractEntities(string text)
        {
            var entities = new List<ExtractedEntity>();

            // Emails
            foreach (Match m in EmailPattern.Matches(text))
                entities.Add(new ExtractedEntity { Text = m.Value, Type = "email", StartIndex = m.Index });

            // URLs
            foreach (Match m in UrlPattern.Matches(text))
                entities.Add(new ExtractedEntity { Text = m.Value, Type = "url", StartIndex = m.Index });

            // File paths
            foreach (Match m in FilePathPattern.Matches(text))
                entities.Add(new ExtractedEntity { Text = m.Value, Type = "file_path", StartIndex = m.Index });

            // Dates
            foreach (Match m in DatePattern.Matches(text))
                entities.Add(new ExtractedEntity { Text = m.Value, Type = "date", StartIndex = m.Index });

            // Numbers/money
            foreach (Match m in NumberPattern.Matches(text))
                entities.Add(new ExtractedEntity { Text = m.Value, Type = "number", StartIndex = m.Index });

            // Detect programming language mentions
            var codeLangs = new[] { "python", "javascript", "typescript", "java", "c#", "csharp",
                "rust", "golang", "go", "ruby", "swift", "kotlin", "dart", "php", "scala",
                "haskell", "ocaml", "elixir", "lua", "perl", "r", "matlab", "sql" };
            var lower = text.ToLowerInvariant();
            foreach (var lang in codeLangs)
            {
                var idx = lower.IndexOf(lang, StringComparison.Ordinal);
                if (idx >= 0)
                {
                    entities.Add(new ExtractedEntity { Text = lang, Type = "code_lang", StartIndex = idx });
                }
            }

            return entities.OrderBy(e => e.StartIndex).ToList();
        }

        private static List<PromptCapability> DetectCapabilities(string text)
        {
            var capabilities = new List<PromptCapability>();
            var lower = text.ToLowerInvariant();

            foreach (var (capability, keywords) in CapabilityKeywords)
            {
                var hits = keywords.Count(k => lower.Contains(k));
                // Require at least 2 keyword hits for non-obvious capabilities,
                // or 1 for very specific ones
                var threshold = capability switch
                {
                    PromptCapability.Translation => 1,
                    PromptCapability.Summarization => 1,
                    _ => 2
                };

                if (hits >= threshold)
                    capabilities.Add(capability);
            }

            // Always include TextGeneration as baseline
            if (!capabilities.Contains(PromptCapability.TextGeneration))
                capabilities.Insert(0, PromptCapability.TextGeneration);

            // Detect StructuredOutput from regex pattern too
            if (!capabilities.Contains(PromptCapability.StructuredOutput) &&
                JsonStructurePattern.IsMatch(text))
                capabilities.Add(PromptCapability.StructuredOutput);

            return capabilities;
        }

        private static (PromptDomain Domain, double Confidence) ClassifyDomain(string text)
        {
            var lower = text.ToLowerInvariant();
            var scores = new Dictionary<PromptDomain, int>();

            foreach (var (domain, keywords) in DomainKeywords)
            {
                var hits = keywords.Count(k => lower.Contains(k));
                if (hits > 0) scores[domain] = hits;
            }

            if (scores.Count == 0)
                return (PromptDomain.General, 0.5);

            var maxPair = scores.OrderByDescending(s => s.Value).First();
            var totalHits = scores.Values.Sum();
            var confidence = Math.Min(1.0, maxPair.Value / Math.Max(1.0, totalHits * 0.6));

            return (maxPair.Key, Math.Round(confidence, 2));
        }

        private static PromptTone AnalyzeTone(string text)
        {
            var formalSignals = 0;
            var casualSignals = 0;
            var lower = text.ToLowerInvariant();

            // Formal indicators
            var formalWords = new[] {
                "hereby", "pursuant", "whereas", "furthermore", "consequently",
                "aforementioned", "notwithstanding", "henceforth", "therein",
                "shall", "kindly", "respectfully", "regarding", "enclosed",
                "in accordance with", "please be advised"
            };
            formalSignals += formalWords.Count(w => lower.Contains(w));

            // Professional indicators
            var proWords = new[] {
                "please", "would you", "could you", "i would like", "appreciate",
                "thank you", "best regards", "sincerely", "dear"
            };
            var proHits = proWords.Count(w => lower.Contains(w));

            // Casual indicators
            var casualWords = new[] {
                "hey", "yo", "gonna", "wanna", "gotta", "lol", "btw", "tbh",
                "ngl", "imo", "bruh", "dude", "nah", "yeah", "cool", "awesome",
                "sup", "omg", "lmao", "haha"
            };
            casualSignals += casualWords.Count(w => lower.Contains(w));

            // Emoji/emoticons as casual signal
            if (text.Any(c => c >= 0x1F600 && c <= 0x1F64F || c >= 0x1F300 && c <= 0x1F5FF))
                casualSignals += 2;

            // Exclamation marks as mild casual signal
            var exclamations = text.Count(c => c == '!');
            if (exclamations > 2) casualSignals++;

            if (formalSignals >= 3) return PromptTone.Formal;
            if (formalSignals >= 1 && casualSignals == 0) return PromptTone.Professional;
            if (casualSignals >= 3) return PromptTone.Informal;
            if (casualSignals >= 1) return PromptTone.Casual;
            if (proHits >= 2) return PromptTone.Professional;
            return PromptTone.Neutral;
        }

        private static string SuggestRouting(PromptMetadata metadata)
        {
            // "specialist" — needs domain expertise or multiple advanced capabilities
            if (metadata.Capabilities.Count >= 4 ||
                (metadata.Domain != PromptDomain.General && metadata.DomainConfidence > 0.7 &&
                 metadata.Capabilities.Any(c => c == PromptCapability.Reasoning ||
                                                c == PromptCapability.CodeGeneration)))
                return "specialist";

            // "premium" — complex multi-capability or long prompt
            if (metadata.Capabilities.Count >= 3 ||
                metadata.EstimatedTokens > 2000 ||
                metadata.HasExamples && metadata.InstructionCount > 3)
                return "premium";

            // "fast" — simple short prompts
            if (metadata.WordCount < 20 &&
                metadata.Capabilities.Count <= 1 &&
                metadata.QuestionCount <= 1)
                return "fast";

            return "standard";
        }

        private static Dictionary<string, string> BuildTags(PromptMetadata metadata, string text)
        {
            var tags = new Dictionary<string, string>();

            tags["word_count_bucket"] = metadata.WordCount switch
            {
                < 10 => "micro",
                < 50 => "short",
                < 200 => "medium",
                < 500 => "long",
                _ => "very_long"
            };

            if (metadata.HasExamples) tags["pattern"] = "few_shot";
            if (metadata.HasSystemDirectives) tags["has_system"] = "true";
            if (metadata.QuestionCount > 0) tags["interaction"] = "question";
            if (metadata.InstructionCount > 0) tags["interaction"] = "instruction";

            var codeEntities = metadata.Entities.Where(e => e.Type == "code_lang").Select(e => e.Text).Distinct();
            var codeLangs = string.Join(",", codeEntities);
            if (!string.IsNullOrEmpty(codeLangs)) tags["code_languages"] = codeLangs;

            return tags;
        }

        private static int CountMatches(Regex pattern, string text)
        {
            try { return pattern.Matches(text).Count; }
            catch (RegexMatchTimeoutException) { return 0; }
        }
    }
}
