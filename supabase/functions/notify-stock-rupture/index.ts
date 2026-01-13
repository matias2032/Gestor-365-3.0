// supabase/functions/notify-stock-rupture/index.ts

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";

// 🔥 CREDENCIAIS FCM (Service Account) - ✅ VALIDADAS
const FCM_SERVICE_ACCOUNT = {
  project_id: "barestoquepush1",
  private_key: `-----BEGIN PRIVATE KEY-----
MIIEvQIBADANBgkqhkiG9w0BAQEFAASCBKcwggSjAgEAAoIBAQC/hfILXET7j04I
aIkPCmWZnexcgO0vgfvyE9WvipI5nltaGxgzK37KMaIxVjFQvqbPwJLhgf6CZ4uH
6Nf6vsHa+2EyF7CJp218b078WJ60gKfyVKL7OxyomIcDMxY1SlASHUuWq0yKVMOF
aYaIXQEc2d7Lwb3WkWEUlgDQUgPuTYHm1T96hqsgLtFP9cnobRlh1skR2Ic49bRs
ZBLzFIhZhEX0Ii5Q+MG/ZAzBng3d5AmCEotEtV2LuCJnazKKrEkx4oX/8aU1zAOs
a2wyiZmTq8SQH8Spd57EC3vDnvQR60ckKG8gBnUQE8vVHjiDa1qMAUbJOz7nUxnS
wH7DL30zAgMBAAECggEAD2Ug87DTCrWWPC7K9Z6MVDDRkw36Atub+PWHM7kbz+3e
wftzkolog7BBrV2UUT1CA2kjZWUhpDHWkXIyCkHTK1sRkQk+c5I1xs7btoUZHMFK
vrv27eLuhs7b63Hr0xTKIuqf7NiQKn5tyQeWfNedA0iwFAjazaiZ+SGlpxkwn7MP
hWmOqLtDMCAQlYaN5jB4ss0LIGP9HAzoG0RwKcLvf0MEi0S3hFD/qe5xIyBDu1mo
xDH4i6fYc5NV6PODGe5af9bX0gkqs+WPtTYdjhTNZeW5aHWEURM2qzQZgM8QS6iA
8cxVAP8XuWLx8C/rmHAWWSDXUk15UG82sCuPkJwZAQKBgQDx3nm9SVRRJMAdLFBw
kyX1RN158P5GtXoCzMexaIfhgF+1P1+ZzHxM1lOhxx+zfUkRQQsQnIS4yWparZgl
AiITeS0K3GX4C/r+Icy+gsdDMqIixuDzZewc8RDLWVU4im3oC43ri1UxgVksOVZG
betFIeFu3glvZU67tWI5y17YUwKBgQDKtnh3x1wluS9NCjlNDQwabfI3u5952qmP
Z2iCSORzbMAUYquCAEgrSrxLzSJ3W99i4RD3wmmXkbgI1GKyr+22S5iI5a82WELA
/AzCFkcgA/jBK3XKI+I2rPC9yIkMEK8aj+Q+H0gRlAq9x57xGDyxP8nntIjpdlQb
Rw0H7I6roQKBgQCazRJLpNgzSvsucMNXGcbMkPPTbPvBk7rwedJBaK63FCutXE86
p1bS8sX6H/DZNxGB2ohTbGnBvx+zw7FB1niqz/6VGfSlaj2NU2KweBFCn/CHo5Qs
FAqnh16BV76kfmzTfDmsDLRNCAVjuZrPXuCakZGwHKobQtK+btvcM56TgwKBgAYV
ifIWYrajIz9NskCUxqs4Z4+yquuuW255bRKT+39XYUB7YahqN8BM4u/nfURV1pOS
K78z75VkA0EIltnEG/9fr3lUY3jfF0nRhtSAdKwKUnoBwuxJPW3krOkVTr+09Hx4
myIeMDyO0++0QRn9Xzz2rCmvKnjPW2DiNgrp17JhAoGActMqvHM4Pg0D3Dddpj9h
U/8/1/8hvQvvIvDSRDvIPTMAlU1SR+4Qn4MNxN+cnM4rLcojpmueJ4TbcOti1njD
pasF+KgwWQwgHQ/7XS/z/rBchIwy912RUdaYv9rZxtNrXF9msliamQxX9yHpyqHe
XsOLDgka2bV950tJDzXU+6M=
-----END PRIVATE KEY-----`,
  client_email: "firebase-adminsdk-fbsvc@barestoquepush1.iam.gserviceaccount.com",
};

const FCM_SCOPE = "https://www.googleapis.com/auth/firebase.messaging";

// 🔥 GERAR ACCESS TOKEN JWT
async function getAccessToken(): Promise<string> {
  const header = { alg: "RS256", typ: "JWT" };
  const now = Math.floor(Date.now() / 1000);
  
  const payload = {
    iss: FCM_SERVICE_ACCOUNT.client_email,
    scope: FCM_SCOPE,
    aud: "https://oauth2.googleapis.com/token",
    exp: now + 3600,
    iat: now,
  };

  // Criar JWT
  const encodedHeader = btoa(JSON.stringify(header));
  const encodedPayload = btoa(JSON.stringify(payload));
  const unsignedToken = `${encodedHeader}.${encodedPayload}`;

  // Assinar com private_key
  const encoder = new TextEncoder();
  const data = encoder.encode(unsignedToken);
  
  // Importar chave privada
  const pemContents = FCM_SERVICE_ACCOUNT.private_key
    .replace(/-----BEGIN PRIVATE KEY-----/, "")
    .replace(/-----END PRIVATE KEY-----/, "")
    .replace(/\n/g, "");
  
  const binaryDer = Uint8Array.from(atob(pemContents), c => c.charCodeAt(0));
  
  const key = await crypto.subtle.importKey(
    "pkcs8",
    binaryDer,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"]
  );
  
  const signature = await crypto.subtle.sign("RSASSA-PKCS1-v1_5", key, data);
  const signatureBase64 = btoa(String.fromCharCode(...new Uint8Array(signature)));
  
  const jwt = `${unsignedToken}.${signatureBase64}`;

  // Trocar JWT por Access Token
  const tokenResponse = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: jwt,
    }),
  });

  const tokenData = await tokenResponse.json();
  
  if (!tokenData.access_token) {
    throw new Error(`Falha ao obter access token: ${JSON.stringify(tokenData)}`);
  }
  
  return tokenData.access_token;
}

// 🔥 ENVIAR NOTIFICAÇÃO FCM
async function sendFCMNotification(accessToken: string, productData: any) {
  const message = {
    message: {
      topic: "estoque_ruptura",
      notification: {
        title: "🚨 RUPTURA DE ESTOQUE!",
        body: `O produto "${productData.nome_produto}" está com estoque ZERADO!`,
      },
      data: {
        id_produto: productData.id_produto.toString(),
        nome_produto: productData.nome_produto,
        quantidade: productData.quantidade_estoque.toString(),
        tipo: "ruptura_estoque",
      },
      android: {
        priority: "high",
        notification: {
          sound: "default",
          color: "#FF0000",
          channel_id: "alerta_ruptura",
        },
      },
      apns: {
        payload: {
          aps: {
            sound: "default",
            badge: 1,
          },
        },
      },
    },
  };

  const response = await fetch(
    `https://fcm.googleapis.com/v1/projects/${FCM_SERVICE_ACCOUNT.project_id}/messages:send`,
    {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${accessToken}`,
      },
      body: JSON.stringify(message),
    }
  );

  const result = await response.json();
  
  if (!response.ok) {
    throw new Error(`FCM API error: ${JSON.stringify(result)}`);
  }
  
  return result;
}

// 🔥 HANDLER PRINCIPAL
serve(async (req) => {
  // CORS headers
  const corsHeaders = {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Access-Control-Allow-Headers": "Content-Type, Authorization",
  };

  // Handle preflight
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: corsHeaders, status: 204 });
  }

  try {
    const { id_produto, nome_produto, quantidade_estoque } = await req.json();

    console.log(`📦 Processando ruptura: Produto ${id_produto} - ${nome_produto}`);

    // Validação
    if (!id_produto || !nome_produto) {
      return new Response(
        JSON.stringify({ success: false, error: "Dados inválidos" }),
        { headers: { ...corsHeaders, "Content-Type": "application/json" }, status: 400 }
      );
    }

    // Obter access token
    const accessToken = await getAccessToken();

    // Enviar notificação
    const result = await sendFCMNotification(accessToken, {
      id_produto,
      nome_produto,
      quantidade_estoque: quantidade_estoque ?? 0,
    });

    console.log("✅ Notificação enviada:", result);

    return new Response(
      JSON.stringify({ success: true, message: "Notificação enviada", result }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" }, status: 200 }
    );
  } catch (error) {
    console.error("❌ Erro ao enviar notificação:", error);
    return new Response(
      JSON.stringify({ success: false, error: error.message }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" }, status: 500 }
    );
  }
});