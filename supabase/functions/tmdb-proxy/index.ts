import "jsr:@supabase/functions-js/edge-runtime.d.ts";

const TMDB_BASE = "https://api.themoviedb.org/3";

const allowedPath =
  /^\/(trending\/(all|movie|tv|person)\/(day|week)|movie(?:\/.*)?|tv(?:\/.*)?|person(?:\/.*)?|search\/(movie|tv|person|multi)|discover\/(movie|tv)|genre\/(movie|tv)\/list|configuration(?:\/.*)?)$/;

Deno.serve(async (req: Request) => {
  const corsHeaders = {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Headers": "authorization, apikey, content-type",
    "Access-Control-Allow-Methods": "GET, OPTIONS",
    "Content-Type": "application/json; charset=utf-8",
  };

  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: corsHeaders });
  }

  if (req.method !== "GET") {
    return Response.json(
      { error: "METHOD_NOT_ALLOWED" },
      { status: 405, headers: corsHeaders },
    );
  }

  const incoming = new URL(req.url);
  const path = incoming.searchParams.get("path") ?? "";

  if (!allowedPath.test(path)) {
    return Response.json(
      { error: "INVALID_TMDB_PATH" },
      { status: 400, headers: corsHeaders },
    );
  }

  const apiKey = Deno.env.get("TMDB_API_KEY");

  if (!apiKey) {
    return Response.json(
      { error: "TMDB_NOT_CONFIGURED" },
      { status: 503, headers: corsHeaders },
    );
  }

  const params = new URLSearchParams(incoming.searchParams);
  params.delete("path");
  params.delete("api_key");
  params.delete("apiKey");
  params.set("api_key", apiKey);

  try {
    const response = await fetch(`${TMDB_BASE}${path}?${params.toString()}`);
    const body = await response.text();

    return new Response(body, {
      status: response.status,
      headers: {
        ...corsHeaders,
        "Content-Type": response.headers.get("Content-Type") ?? "application/json",
      },
    });
  } catch (error) {
    console.error("TMDB upstream error:", error);

    return Response.json(
      { error: "TMDB_UPSTREAM_ERROR" },
      { status: 502, headers: corsHeaders },
    );
  }
});
