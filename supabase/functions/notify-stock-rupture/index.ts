import { serve } from "https://deno.land/std@0.168.0/http/server.ts";

// 🔥 CREDENCIAIS GESTOR365PUSH1 (CONFIRMADAS)
const FCM_SERVICE_ACCOUNT = {
  project_id: "gestor365push1",
  client_email: "firebase-adminsdk-fbsvc@gestor365push1.iam.gserviceaccount.com",
  private_key: `-----BEGIN PRIVATE KEY-----
MIIEvgIBADANBgkqhkiG9w0BAQEFAASCBKgwggSkAgEAAoIBAQDVCKuVo7jZwqmR
MZNopnlaEsjHTlnTkZgjnGpnAqt2wBt+pNRoK80WgUC5PyaHSq1hrjKvf3T8s0j7
LRw6YjoFc3KRcSMpNLIHPeIzOHuk5PIeq0433fKjoIbzaJ3h/mjnbPcudKHXvdZW
qyU/mFnudlmPPrJMmLgSwVAgNbvTMsQIRIPPjlTrAr38fireGbIZYqvNrD0mf4u3
u/j1qHURK7ttYBuDtBgmLSvhUZt+tswiMzF+X08be/Ps9eSVvp1Ql2Qeqwv4gclP
EUrmfeFHBV3Ui76Mfe62KL98CRcCB4vJxzE/qhrykitS4/V7eSyzsqJIGpB8cER5
Dq96h30RAgMBAAECggEABpj0RGf7vm21heg6xBXMwg39HxQFeuSCSU8LqglGgWDZ
cSJ+bAP4P+NMm3gR08SLqk/kZLQ+LaHJR7MZ0dKPMLJGuOufrsPhpBEF73dnN9/5
whqky1zhqfDboQ/rPM+d1NX2cT8+MGHiEJDQEGBB371VUHb8+1uK7tTDDB5R5OxZ
8MYWNpBq28Nkf6oQKB66iVl1EB0A/4myfkHJlzjjqfBwK+bPBbWBn9Wj3cG6Yy89
H0yxeImNwksBtHBMF7q0h1qxHlqY4OA7J73iOjjF0f42v7deu0adPZd4ScLC0wnw
X5sSP7eLqwsrIyE6EEmWL8ughXn3ebHSlbi4zE3jKQKBgQD4tUogU98+7/CDAUFd
+IOsZwKRdNp28Glzmt2UewiJ7mb6JOsVPS095qhKn+4j0WUOsw7Z1d97dYYewXps
+idNCSSo9PVb8M4w7PKhZ8BvZgJ1TORpGgkWHdtGtIYww1V95PtfGvM/E++Wzl/K
4Thw6v1PqmtvrO+GV0dEyjRzyQKBgQDbR59u/UiVBRUxZ2tNbvU3VePf0B2k6EER
0+XOYY774rpl88876Sd4gBi+dMJxNUHvUHvT8pk8h8P6u4I2GEQk/h9ASgT+wWKV
T++mgH11kPn8S0jeI8EDAyQhrA5Dn5QoB2UOwrha+76rPy1AyL619x3goI4af9g+
KnGAuhuTCQKBgF/m0BGNJd2H+g8aEdGhfWyiP/xEueT5KUB5rA2QL6e4NR8p0zha
YbKn2acE6ngHS1eSthxLeySJGdGMO6AACd2LtAYuhtoQDgIRrDGO50ZNaI9AuibI
8k4D70ThYYk2GSY1gLSYmMlu74kQRSHfHLt18X2hslHatnXv+7xL2FP5AoGBAM9u
lZe86mhuAnpVxt/dUwMhsQsMKL7TJprixMXS7BvDg2jmluepy7jmFII2manWI6Vr
kXgSSntEQ1RxBOB/XBdSfeWnH8qOzd9JWv87FXOdzZ2o6imZ0QA0fH2N8YBu+QxU
0niAIz2OX/RHM1vRivc/6XeQ6lyPC9Ti+bQ4WdVhAoGBAO5zgPqJs4vFnEYdnhFs
aoH8HcZfllM2Y5eqT5OPYeXWXX47QyB+r0gb7nE2nfNika7xrQYbGsLTvCvm963S
BH26qGAzzKeTbctOsRuwZsF4w/Y7acNj9ZDYbNXS1dFhp9RelwqZXe+WYT9wO1eG
0IA+xw068wpDxDDPENdnAtKh
-----END PRIVATE KEY-----`,
};

const FCM_SCOPE = "https://www.googleapis.com/auth/firebase.messaging";

// 🔥 FUNÇÃO AUXILIAR: GERAR ACCESS TOKEN JWT
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

  const encodedHeader = btoa(JSON.stringify(header));
  const encodedPayload = btoa(JSON.stringify(payload));
  const unsignedToken = `${encodedHeader}.${encodedPayload}`;

  const encoder = new TextEncoder();
  const data = encoder.encode(unsignedToken);
  
  // Limpeza robusta da chave
  const pemContents = FCM_SERVICE_ACCOUNT.private_key
    .replace(/-----BEGIN PRIVATE KEY-----/, "")
    .replace(/-----END PRIVATE KEY-----/, "")
    .replace(/\s/g, ""); // Remove espaços e quebras de linha com segurança
  
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
    throw new Error(`Falha no token: ${JSON.stringify(tokenData)}`);
  }
  
  return tokenData.access_token;
}

// 🔥 ENVIAR NOTIFICAÇÃO (Versão Completa Restaurada)
async function sendFCMNotification(accessToken: string, productData: any) {
  const message = {
    message: {
      topic: "estoque_ruptura",
      notification: {
        title: " RUPTURA DE ESTOQUE!",
        body: `O produto "${productData.nome_produto}" está com estoque ZERADO!`,
      },
      // Dados extras para o App usar ao clicar na notificação
      data: {
        id_produto: productData.id_produto.toString(),
        nome_produto: productData.nome_produto,
        quantidade: (productData.quantidade_estoque ?? 0).toString(),
        tipo: "ruptura_estoque",
      },
      // Configurações Específicas para Android (Restauradas)
      android: {
        priority: "high",
        notification: {
          sound: "default",
          color: "#FF0000", // Vermelho Alerta
          channel_id: "alerta_ruptura",
        },
      },
      // Configurações Específicas para iOS (Restauradas)
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
     throw new Error(`FCM API Error: ${JSON.stringify(result)}`);
  }

  return result;
}

// 🔥 HANDLER PRINCIPAL (SERVE)
serve(async (req) => {
  const corsHeaders = {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Access-Control-Allow-Headers": "Content-Type, Authorization",
  };

  if (req.method === "OPTIONS") return new Response(null, { headers: corsHeaders, status: 204 });

  try {
    const { id_produto, nome_produto, quantidade_estoque } = await req.json();
    
    // Log restaurado para Debug
    console.log(`📦 Processando ruptura: ${nome_produto} (ID: ${id_produto})`);

    // Validação restaurada
    if (!id_produto || !nome_produto) {
        throw new Error("Dados inválidos: id_produto ou nome_produto faltando.");
    }

    const accessToken = await getAccessToken();
    
    // Passando o objeto completo restaurado
    const result = await sendFCMNotification(accessToken, { 
        id_produto, 
        nome_produto, 
        quantidade_estoque 
    });

    console.log("✅ Notificação enviada com sucesso!");

    return new Response(JSON.stringify({ success: true, result }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
      status: 200,
    });
  } catch (error) {
    console.error("❌ Erro na função:", error);
    return new Response(JSON.stringify({ success: false, error: error.message }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
      status: 500,
    });
  }
});