<!DOCTYPE html>
<html lang="en">
  <head>
    <meta charset="utf-8">
    <meta http-equiv="x-ua-compatible" content="ie=edge">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <meta name="generator" content="ExDoc v0.39.1">
    <meta name="project" content="ash_agent v0.1.0">


    <title>AshAgent.ProgressiveDisclosure — ash_agent v0.1.0</title>

    <link rel="stylesheet" href="dist/html-elixir-ZFNMEJKT.css" />

    <script defer src="dist/sidebar_items-943756EC.js"></script>
    <script defer src="docs_config.js"></script>
    <script defer src="dist/html-HBZYRXZS.js"></script>
<script src="https://cdn.jsdelivr.net/npm/mermaid@10.2.0/dist/mermaid.min.js"></script>
<script>
  document.addEventListener("DOMContentLoaded", function () {
    mermaid.initialize({
      startOnLoad: false,
      theme: document.body.className.includes("dark") ? "dark" : "default"
    });
    let id = 0;
    for (const codeEl of document.querySelectorAll("pre code.mermaid")) {
      const preEl = codeEl.parentElement;
      const graphDefinition = codeEl.textContent;
      const graphEl = document.createElement("div");
      const graphId = "mermaid-graph-" + id++;
      mermaid.render(graphId, graphDefinition).then(({svg, bindFunctions}) => {
        graphEl.innerHTML = svg;
        bindFunctions?.(graphEl);
        preEl.insertAdjacentElement("afterend", graphEl);
        preEl.remove();
      });
    }
  });
</script>

  </head>
  <body>
    <script>(()=>{var t="ex_doc:settings",e="dark";var o="dark",s="light";var E="sidebar_state",n="closed";var r="sidebar_width";var a="sidebar-open";var i=new URLSearchParams(window.location.search),S=i.get("theme")||JSON.parse(localStorage.getItem(t)||"{}").theme;(S===o||S!==s&&window.matchMedia("(prefers-color-scheme: dark)").matches)&&document.body.classList.add(e);var d=sessionStorage.getItem(E),A=d!==n&&!window.matchMedia(`screen and (max-width: ${768}px)`).matches;document.body.classList.toggle(a,A);var c=sessionStorage.getItem(r);c&&document.body.style.setProperty("--sidebarWidth",`${c}px`);var p=/(Macintosh|iPhone|iPad|iPod)/.test(window.navigator.userAgent);document.documentElement.classList.toggle("apple-os",p);})();
</script>

<div class="body-wrapper">

<button id="sidebar-menu" class="sidebar-button sidebar-toggle" aria-label="toggle sidebar" aria-controls="sidebar">
  <i class="ri-menu-line ri-lg" title="Collapse/expand sidebar"></i>
</button>

<nav id="sidebar" class="sidebar">

  <div class="sidebar-header">
    <div class="sidebar-projectInfo">

      <div>
        <a href="readme.html" class="sidebar-projectName" translate="no">
ash_agent
        </a>
        <div class="sidebar-projectVersion" translate="no">
          v0.1.0
        </div>
      </div>
    </div>
    <ul id="sidebar-list-nav" class="sidebar-list-nav" role="tablist" data-extras=""></ul>
  </div>
</nav>

<output role="status" id="toast"></output>

<main class="content page-module" id="main" data-type="modules">
  <div id="content" class="content-inner">
    <div class="top-search">
      <div class="search-settings">
        <form class="search-bar" action="search.html">
          <label class="search-label">
            <span class="sr-only">Search documentation of ash_agent</span>
            <div class="search-input-wrapper">
              <input name="q" type="text" class="search-input" placeholder="Press / to search" autocomplete="off" autocorrect="off" autocapitalize="off" spellcheck="false" />
              <button type="button" tabindex="-1" class="search-close-button" aria-hidden="true">
                <i class="ri-close-line ri-lg" title="Cancel search"></i>
              </button>
            </div>
          </label>
        </form>
        <div class="autocomplete">
        </div>
        <div class="engine-selector" data-multiple="false">
          <button type="button" class="engine-button" aria-label="Select search engine" aria-haspopup="true" aria-expanded="false">
            <i class="ri-search-2-line" aria-hidden="true"></i>
            <span class="engine-name">Default</span>
            <i class="ri-arrow-down-s-line" aria-hidden="true"></i>
          </button>
          <div class="engine-dropdown" hidden role="menu">

              <button type="button"
                      class="engine-option"
                      data-engine-url="search.html?q="
                      role="menuitemradio"
                      aria-checked="true">
                <span class="name">Default</span>
                <span class="help">In-browser search</span>
              </button>

          </div>
        </div>
        <button class="icon-settings display-settings">
          <i class="ri-settings-3-line"></i>
          <span class="sr-only">Settings</span>
        </button>
      </div>
    </div>

<div id="top-content">
  <div class="heading-with-actions top-heading">
    <h1>
      <span translate="no">AshAgent.ProgressiveDisclosure</span> 
      <small class="app-vsn" translate="no">(ash_agent v0.1.0)</small>

    </h1>

      <a href="https://github.com/bradleygolden/ash_agent/blob/v0.1.0/lib/ash_agent/progressive_disclosure.ex#L1" title="View Source" class="icon-action" rel="help">
        <i class="ri-code-s-slash-line" aria-hidden="true"></i>
        <span class="sr-only">View Source</span>
      </a>

  </div>


    <section id="moduledoc">
<p>Helper utilities for implementing Progressive Disclosure patterns.</p><p>This module provides high-level functions for common Progressive Disclosure
scenarios:</p><ul><li><strong>Result Processing</strong>: Truncate, summarize, or sample large tool results</li><li><strong>Context Compaction</strong>: Remove old iterations using sliding window or token budget</li></ul><h2 id="module-quick-start" class="section-heading"><a href="#module-quick-start" class="hover-link"><i class="ri-link-m" aria-hidden="true"></i></a><span class="text">Quick Start</span></h2><p>Use in your hook implementations:</p><pre><code class="makeup elixir" translate="no"><span class="kd">defmodule</span><span class="w"> </span><span class="nc">MyApp.PDHooks</span><span class="w"> </span><span class="k" data-group-id="0452523151-1">do</span><span class="w">
  </span><span class="na">@behaviour</span><span class="w"> </span><span class="nc">AshAgent.Runtime.Hooks</span><span class="w">

  </span><span class="kn">alias</span><span class="w"> </span><span class="nc">AshAgent.ProgressiveDisclosure</span><span class="w">

  </span><span class="kd">def</span><span class="w"> </span><span class="nf">prepare_tool_results</span><span class="p" data-group-id="0452523151-2">(</span><span class="p" data-group-id="0452523151-3">%{</span><span class="ss">results</span><span class="p">:</span><span class="w"> </span><span class="n">results</span><span class="p" data-group-id="0452523151-3">}</span><span class="p" data-group-id="0452523151-2">)</span><span class="w"> </span><span class="k" data-group-id="0452523151-4">do</span><span class="w">
    </span><span class="n">processed</span><span class="w"> </span><span class="o">=</span><span class="w"> </span><span class="nc">ProgressiveDisclosure</span><span class="o">.</span><span class="n">process_tool_results</span><span class="p" data-group-id="0452523151-5">(</span><span class="n">results</span><span class="p">,</span><span class="w">
      </span><span class="ss">truncate</span><span class="p">:</span><span class="w"> </span><span class="mi">1000</span><span class="p">,</span><span class="w">
      </span><span class="ss">summarize</span><span class="p">:</span><span class="w"> </span><span class="no">true</span><span class="p">,</span><span class="w">
      </span><span class="ss">sample</span><span class="p">:</span><span class="w"> </span><span class="mi">5</span><span class="w">
    </span><span class="p" data-group-id="0452523151-5">)</span><span class="w">
    </span><span class="p" data-group-id="0452523151-6">{</span><span class="ss">:ok</span><span class="p">,</span><span class="w"> </span><span class="n">processed</span><span class="p" data-group-id="0452523151-6">}</span><span class="w">
  </span><span class="k" data-group-id="0452523151-4">end</span><span class="w">

  </span><span class="kd">def</span><span class="w"> </span><span class="nf">prepare_context</span><span class="p" data-group-id="0452523151-7">(</span><span class="p" data-group-id="0452523151-8">%{</span><span class="ss">context</span><span class="p">:</span><span class="w"> </span><span class="n">ctx</span><span class="p" data-group-id="0452523151-8">}</span><span class="p" data-group-id="0452523151-7">)</span><span class="w"> </span><span class="k" data-group-id="0452523151-9">do</span><span class="w">
    </span><span class="n">compacted</span><span class="w"> </span><span class="o">=</span><span class="w"> </span><span class="nc">ProgressiveDisclosure</span><span class="o">.</span><span class="n">sliding_window_compact</span><span class="p" data-group-id="0452523151-10">(</span><span class="n">ctx</span><span class="p">,</span><span class="w"> </span><span class="ss">window_size</span><span class="p">:</span><span class="w"> </span><span class="mi">5</span><span class="p" data-group-id="0452523151-10">)</span><span class="w">
    </span><span class="p" data-group-id="0452523151-11">{</span><span class="ss">:ok</span><span class="p">,</span><span class="w"> </span><span class="n">compacted</span><span class="p" data-group-id="0452523151-11">}</span><span class="w">
  </span><span class="k" data-group-id="0452523151-9">end</span><span class="w">
</span><span class="k" data-group-id="0452523151-1">end</span></code></pre><h2 id="module-architecture" class="section-heading"><a href="#module-architecture" class="hover-link"><i class="ri-link-m" aria-hidden="true"></i></a><span class="text">Architecture</span></h2><p>This module serves as a <strong>convenience layer</strong> over:</p><ul><li><code class="inline">AshAgent.ResultProcessors.*</code> - Individual result processors</li><li><a href="AshAgent.Context.html"><code class="inline">AshAgent.Context</code></a> helpers - Context manipulation functions</li></ul><p>It provides:</p><ul><li>Processor composition (apply multiple processors in sequence)</li><li>Common compaction strategies (sliding window, token-based)</li><li>Telemetry integration (track PD usage)</li><li>Sensible defaults (skip processing for small results)</li></ul><h2 id="module-see-also" class="section-heading"><a href="#module-see-also" class="hover-link"><i class="ri-link-m" aria-hidden="true"></i></a><span class="text">See Also</span></h2><ul><li>Progressive Disclosure Guide: <code class="inline">documentation/guides/progressive-disclosure.md</code></li><li>Hook System: <a href="AshAgent.Runtime.Hooks.html"><code class="inline">AshAgent.Runtime.Hooks</code></a></li><li>Result Processors: <code class="inline">AshAgent.ResultProcessors.*</code></li></ul>
    </section>

</div>

  <section id="summary" class="details-list">
    <h1 class="section-heading">
      <a class="hover-link" href="#summary">
        <i class="ri-link-m" aria-hidden="true"></i>
      </a>
      <span class="text">Summary</span>
    </h1>
<div class="summary-functions summary">
  <h2>
    <a href="#functions">Functions</a>
  </h2>

    <div class="summary-row">
      <div class="summary-signature">
        <a href="#process_tool_results/2" data-no-tooltip="" translate="no">process_tool_results(results, opts \\ [])</a>

      </div>

        <div class="summary-synopsis"><p>Applies a standard tool result processing pipeline.</p></div>

    </div>

    <div class="summary-row">
      <div class="summary-signature">
        <a href="#sliding_window_compact/2" data-no-tooltip="" translate="no">sliding_window_compact(context, opts)</a>

      </div>

        <div class="summary-synopsis"><p>Applies sliding window context compaction.</p></div>

    </div>

    <div class="summary-row">
      <div class="summary-signature">
        <a href="#token_based_compact/2" data-no-tooltip="" translate="no">token_based_compact(context, opts)</a>

      </div>

        <div class="summary-synopsis"><p>Applies token-based context compaction.</p></div>

    </div>

</div>

  </section>


  <section id="functions" class="details-list">
    <h1 class="section-heading">
      <a class="hover-link" href="#functions">
        <i class="ri-link-m" aria-hidden="true"></i>
      </a>
      <span class="text">Functions</span>
    </h1>

    <div class="functions-list">
<section class="detail" id="process_tool_results/2">

    <span id="process_tool_results/1"></span>

  <div class="detail-header">
    <a href="#process_tool_results/2" class="detail-link" data-no-tooltip="" aria-label="Link to this function">
      <i class="ri-link-m" aria-hidden="true"></i>
    </a>
    <div class="heading-with-actions">
      <h1 class="signature" translate="no">process_tool_results(results, opts \\ [])</h1>


        <a href="https://github.com/bradleygolden/ash_agent/blob/v0.1.0/lib/ash_agent/progressive_disclosure.ex#L90" class="icon-action" rel="help" aria-label="View Source">
          <i class="ri-code-s-slash-line" aria-hidden="true"></i>
        </a>

    </div>
  </div>

  <section class="docstring">

      <div class="specs">

          <pre translate="no"><span class="attribute">@spec</span> process_tool_results(
  [<a href="AshAgent.ResultProcessor.html#t:result_entry/0">AshAgent.ResultProcessor.result_entry</a>()],
  <a href="https://hexdocs.pm/elixir/typespecs.html#built-in-types">keyword</a>()
) :: [<a href="AshAgent.ResultProcessor.html#t:result_entry/0">AshAgent.ResultProcessor.result_entry</a>()]</pre>

      </div>

<p>Applies a standard tool result processing pipeline.</p><p>Composes multiple processors in sequence:</p><ol><li>Check if any results are large (skip processing if all small)</li><li>Apply truncation (if configured)</li><li>Apply summarization (if configured)</li><li>Apply sampling (if configured)</li><li>Emit telemetry</li></ol><h2 id="process_tool_results/2-options" class="section-heading"><a href="#process_tool_results/2-options" class="hover-link"><i class="ri-link-m" aria-hidden="true"></i></a><span class="text">Options</span></h2><ul><li><code class="inline">:truncate</code> - Max size for truncation (integer, default: no truncation)</li><li><code class="inline">:summarize</code> - Enable summarization (boolean or keyword, default: false)</li><li><code class="inline">:sample</code> - Sample size for lists (integer, default: no sampling)</li><li><code class="inline">:skip_small</code> - Skip processing if all results under threshold (boolean, default: true)</li></ul><h2 id="process_tool_results/2-examples" class="section-heading"><a href="#process_tool_results/2-examples" class="hover-link"><i class="ri-link-m" aria-hidden="true"></i></a><span class="text">Examples</span></h2><pre><code class="makeup elixir" translate="no"><span class="gp unselectable">iex&gt; </span><span class="n">results</span><span class="w"> </span><span class="o">=</span><span class="w"> </span><span class="p" data-group-id="8366245443-1">[</span><span class="p" data-group-id="8366245443-2">{</span><span class="s">&quot;query&quot;</span><span class="p">,</span><span class="w"> </span><span class="p" data-group-id="8366245443-3">{</span><span class="ss">:ok</span><span class="p">,</span><span class="w"> </span><span class="n">large_data</span><span class="p" data-group-id="8366245443-3">}</span><span class="p" data-group-id="8366245443-2">}</span><span class="p" data-group-id="8366245443-1">]</span><span class="w">
</span><span class="gp unselectable">iex&gt; </span><span class="n">processed</span><span class="w"> </span><span class="o">=</span><span class="w"> </span><span class="nc">ProgressiveDisclosure</span><span class="o">.</span><span class="n">process_tool_results</span><span class="p" data-group-id="8366245443-4">(</span><span class="n">results</span><span class="p">,</span><span class="w">
</span><span class="gp unselectable">...&gt; </span><span class="w">  </span><span class="ss">truncate</span><span class="p">:</span><span class="w"> </span><span class="mi">1000</span><span class="p">,</span><span class="w">
</span><span class="gp unselectable">...&gt; </span><span class="w">  </span><span class="ss">summarize</span><span class="p">:</span><span class="w"> </span><span class="no">true</span><span class="w">
</span><span class="gp unselectable">...&gt; </span><span class="p" data-group-id="8366245443-4">)</span></code></pre><h2 id="process_tool_results/2-telemetry" class="section-heading"><a href="#process_tool_results/2-telemetry" class="hover-link"><i class="ri-link-m" aria-hidden="true"></i></a><span class="text">Telemetry</span></h2><p>Emits <code class="inline">[:ash_agent, :progressive_disclosure, :process_results]</code> event with:</p><ul><li>Measurements: <code class="inline">%{count: integer(), skipped: boolean()}</code></li><li>Metadata: <code class="inline">%{options: keyword()}</code></li></ul>
  </section>
</section>
<section class="detail" id="sliding_window_compact/2">

  <div class="detail-header">
    <a href="#sliding_window_compact/2" class="detail-link" data-no-tooltip="" aria-label="Link to this function">
      <i class="ri-link-m" aria-hidden="true"></i>
    </a>
    <div class="heading-with-actions">
      <h1 class="signature" translate="no">sliding_window_compact(context, opts)</h1>


        <a href="https://github.com/bradleygolden/ash_agent/blob/v0.1.0/lib/ash_agent/progressive_disclosure.ex#L225" class="icon-action" rel="help" aria-label="View Source">
          <i class="ri-code-s-slash-line" aria-hidden="true"></i>
        </a>

    </div>
  </div>

  <section class="docstring">

      <div class="specs">

          <pre translate="no"><span class="attribute">@spec</span> sliding_window_compact(
  <a href="AshAgent.Context.html#t:t/0">AshAgent.Context.t</a>(),
  <a href="https://hexdocs.pm/elixir/typespecs.html#built-in-types">keyword</a>()
) :: <a href="AshAgent.Context.html#t:t/0">AshAgent.Context.t</a>()</pre>

      </div>

<p>Applies sliding window context compaction.</p><p>Keeps the last N iterations in full detail, removes older ones.
This is the <strong>simplest</strong> and most <strong>predictable</strong> compaction strategy.</p><h2 id="sliding_window_compact/2-options" class="section-heading"><a href="#sliding_window_compact/2-options" class="hover-link"><i class="ri-link-m" aria-hidden="true"></i></a><span class="text">Options</span></h2><ul><li><code class="inline">:window_size</code> - Number of recent iterations to keep (required)</li></ul><h2 id="sliding_window_compact/2-examples" class="section-heading"><a href="#sliding_window_compact/2-examples" class="hover-link"><i class="ri-link-m" aria-hidden="true"></i></a><span class="text">Examples</span></h2><pre><code class="makeup elixir" translate="no"><span class="gp unselectable">iex&gt; </span><span class="n">context</span><span class="w"> </span><span class="o">=</span><span class="w"> </span><span class="p" data-group-id="5244264528-1">%</span><span class="nc" data-group-id="5244264528-1">AshAgent.Context</span><span class="p" data-group-id="5244264528-1">{</span><span class="ss">iterations</span><span class="p">:</span><span class="w"> </span><span class="p" data-group-id="5244264528-2">[</span><span class="mi">1</span><span class="p">,</span><span class="w"> </span><span class="mi">2</span><span class="p">,</span><span class="w"> </span><span class="mi">3</span><span class="p">,</span><span class="w"> </span><span class="mi">4</span><span class="p">,</span><span class="w"> </span><span class="mi">5</span><span class="p" data-group-id="5244264528-2">]</span><span class="p" data-group-id="5244264528-1">}</span><span class="w">
</span><span class="gp unselectable">iex&gt; </span><span class="n">compacted</span><span class="w"> </span><span class="o">=</span><span class="w"> </span><span class="nc">AshAgent.ProgressiveDisclosure</span><span class="o">.</span><span class="n">sliding_window_compact</span><span class="p" data-group-id="5244264528-3">(</span><span class="w">
</span><span class="gp unselectable">...&gt; </span><span class="w">  </span><span class="n">context</span><span class="p">,</span><span class="w">
</span><span class="gp unselectable">...&gt; </span><span class="w">  </span><span class="ss">window_size</span><span class="p">:</span><span class="w"> </span><span class="mi">3</span><span class="w">
</span><span class="gp unselectable">...&gt; </span><span class="p" data-group-id="5244264528-3">)</span><span class="w">
</span><span class="gp unselectable">iex&gt; </span><span class="n">length</span><span class="p" data-group-id="5244264528-4">(</span><span class="n">compacted</span><span class="o">.</span><span class="n">iterations</span><span class="p" data-group-id="5244264528-4">)</span><span class="w">
</span><span class="mi">3</span></code></pre><h2 id="sliding_window_compact/2-when-to-use" class="section-heading"><a href="#sliding_window_compact/2-when-to-use" class="hover-link"><i class="ri-link-m" aria-hidden="true"></i></a><span class="text">When to Use</span></h2><ul><li>Fixed iteration history limit</li><li>Predictable memory usage</li><li>Simple configuration</li></ul><h2 id="sliding_window_compact/2-telemetry" class="section-heading"><a href="#sliding_window_compact/2-telemetry" class="hover-link"><i class="ri-link-m" aria-hidden="true"></i></a><span class="text">Telemetry</span></h2><p>Emits <code class="inline">[:ash_agent, :progressive_disclosure, :sliding_window]</code> event with:</p><ul><li>Measurements: <code class="inline">%{before_count: int, after_count: int, removed: int}</code></li><li>Metadata: <code class="inline">%{window_size: int}</code></li></ul>
  </section>
</section>
<section class="detail" id="token_based_compact/2">

  <div class="detail-header">
    <a href="#token_based_compact/2" class="detail-link" data-no-tooltip="" aria-label="Link to this function">
      <i class="ri-link-m" aria-hidden="true"></i>
    </a>
    <div class="heading-with-actions">
      <h1 class="signature" translate="no">token_based_compact(context, opts)</h1>


        <a href="https://github.com/bradleygolden/ash_agent/blob/v0.1.0/lib/ash_agent/progressive_disclosure.ex#L292" class="icon-action" rel="help" aria-label="View Source">
          <i class="ri-code-s-slash-line" aria-hidden="true"></i>
        </a>

    </div>
  </div>

  <section class="docstring">

      <div class="specs">

          <pre translate="no"><span class="attribute">@spec</span> token_based_compact(
  <a href="AshAgent.Context.html#t:t/0">AshAgent.Context.t</a>(),
  <a href="https://hexdocs.pm/elixir/typespecs.html#built-in-types">keyword</a>()
) :: <a href="AshAgent.Context.html#t:t/0">AshAgent.Context.t</a>()</pre>

      </div>

<p>Applies token-based context compaction.</p><p>Removes oldest iterations until context is under token budget.
Preserves at least 1 iteration for safety.</p><h2 id="token_based_compact/2-options" class="section-heading"><a href="#token_based_compact/2-options" class="hover-link"><i class="ri-link-m" aria-hidden="true"></i></a><span class="text">Options</span></h2><ul><li><code class="inline">:budget</code> - Maximum token budget (required)</li><li><code class="inline">:threshold</code> - Utilization threshold to trigger compaction (default: 1.0)</li></ul><h2 id="token_based_compact/2-examples" class="section-heading"><a href="#token_based_compact/2-examples" class="hover-link"><i class="ri-link-m" aria-hidden="true"></i></a><span class="text">Examples</span></h2><pre><code class="makeup elixir" translate="no"><span class="gp unselectable">iex&gt; </span><span class="n">large_context</span><span class="w"> </span><span class="o">=</span><span class="w"> </span><span class="p" data-group-id="5705453593-1">%</span><span class="nc" data-group-id="5705453593-1">AshAgent.Context</span><span class="p" data-group-id="5705453593-1">{</span><span class="ss">iterations</span><span class="p">:</span><span class="w"> </span><span class="nc">List</span><span class="o">.</span><span class="n">duplicate</span><span class="p" data-group-id="5705453593-2">(</span><span class="p" data-group-id="5705453593-3">%{</span><span class="ss">messages</span><span class="p">:</span><span class="w"> </span><span class="p" data-group-id="5705453593-4">[</span><span class="p" data-group-id="5705453593-5">%{</span><span class="ss">content</span><span class="p">:</span><span class="w"> </span><span class="nc">String</span><span class="o">.</span><span class="n">duplicate</span><span class="p" data-group-id="5705453593-6">(</span><span class="s">&quot;x&quot;</span><span class="p">,</span><span class="w"> </span><span class="mi">1000</span><span class="p" data-group-id="5705453593-6">)</span><span class="p" data-group-id="5705453593-5">}</span><span class="p" data-group-id="5705453593-4">]</span><span class="p" data-group-id="5705453593-3">}</span><span class="p">,</span><span class="w"> </span><span class="mi">10</span><span class="p" data-group-id="5705453593-2">)</span><span class="p" data-group-id="5705453593-1">}</span><span class="w">
</span><span class="gp unselectable">iex&gt; </span><span class="n">compacted</span><span class="w"> </span><span class="o">=</span><span class="w"> </span><span class="nc">AshAgent.ProgressiveDisclosure</span><span class="o">.</span><span class="n">token_based_compact</span><span class="p" data-group-id="5705453593-7">(</span><span class="w">
</span><span class="gp unselectable">...&gt; </span><span class="w">  </span><span class="n">large_context</span><span class="p">,</span><span class="w">
</span><span class="gp unselectable">...&gt; </span><span class="w">  </span><span class="ss">budget</span><span class="p">:</span><span class="w"> </span><span class="mi">100</span><span class="w">
</span><span class="gp unselectable">...&gt; </span><span class="p" data-group-id="5705453593-7">)</span><span class="w">
</span><span class="gp unselectable">iex&gt; </span><span class="nc">AshAgent.Context</span><span class="o">.</span><span class="n">estimate_token_count</span><span class="p" data-group-id="5705453593-8">(</span><span class="n">compacted</span><span class="p" data-group-id="5705453593-8">)</span><span class="w"> </span><span class="o">&lt;=</span><span class="w"> </span><span class="mi">100</span><span class="w"> </span><span class="ow">or</span><span class="w"> </span><span class="nc">AshAgent.Context</span><span class="o">.</span><span class="n">count_iterations</span><span class="p" data-group-id="5705453593-9">(</span><span class="n">compacted</span><span class="p" data-group-id="5705453593-9">)</span><span class="w"> </span><span class="o">==</span><span class="w"> </span><span class="mi">1</span><span class="w">
</span><span class="no">true</span></code></pre><h2 id="token_based_compact/2-when-to-use" class="section-heading"><a href="#token_based_compact/2-when-to-use" class="hover-link"><i class="ri-link-m" aria-hidden="true"></i></a><span class="text">When to Use</span></h2><ul><li>Token budget constraints</li><li>Cost optimization</li><li>Dynamic history size based on content</li></ul><h2 id="token_based_compact/2-telemetry" class="section-heading"><a href="#token_based_compact/2-telemetry" class="hover-link"><i class="ri-link-m" aria-hidden="true"></i></a><span class="text">Telemetry</span></h2><p>Emits <code class="inline">[:ash_agent, :progressive_disclosure, :token_based]</code> event with:</p><ul><li>Measurements: <code class="inline">%{before_count: int, after_count: int, removed: int, final_tokens: int}</code></li><li>Metadata: <code class="inline">%{budget: int, threshold: float}</code></li></ul>
  </section>
</section>

    </div>
  </section>

    <footer class="footer">
      <p>

          <span class="line">
            <a href="https://hex.pm/packages/ash_agent/0.1.0" class="footer-hex-package">Hex Package</a>

            <a href="https://preview.hex.pm/preview/ash_agent/0.1.0">Hex Preview</a>

          </span>

        <span class="line">
          <button class="a-main footer-button display-quick-switch" title="Search HexDocs packages">
            Search HexDocs
          </button>

            <a href="ash_agent.epub" title="ePub version">
              Download ePub version
            </a>

        </span>
      </p>

      <p class="built-using">
        Built using
        <a href="https://github.com/elixir-lang/ex_doc" title="ExDoc" target="_blank" rel="help noopener" translate="no">ExDoc</a> (v0.39.1) for the

          <a href="https://elixir-lang.org" title="Elixir" target="_blank" translate="no">Elixir programming language</a>

      </p>

    </footer>
  </div>
</main>
</div>

  </body>
</html>
