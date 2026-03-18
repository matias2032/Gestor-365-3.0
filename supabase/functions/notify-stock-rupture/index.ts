import { serve } from "https://deno.land/std@0.168.0/http/server.ts";

// 🔥 CREDENCIAIS GESTOR-365PUSH2 (ATUALIZADAS)
const FCM_SERVICE_ACCOUNT = {
  project_id: "gestor-365push2",
  client_email: "firebase-adminsdk-fbsvc@gestor-365push2.iam.gserviceaccount.com",
  private_key: `-----BEGIN PRIVATE KEY-----
MIIEvAIBADANBgkqhkiG9w0BAQEFAASCBKYwggSiAgEAAoIBAQDIfaD2tOy8nCmR
So4OVoLqo07VKiqhgAqlSv9UQtmhPspgjTXsq5uJwpRE1ILeW6NHBZ4eSUIMZ7La
x57WlD0fICLkVQXjd0dBXHyShkzon4cZt7+CCzUOujaO1o1N8rwh3dmTvOseOcDo
Gx1zuPNulzzZyNXMgbxoY2nSNdsrFHg5jfUlUAyMr3kUV5Mr5OGx/LPpdNDGN7oL
4MkQENCH+F88HRBcad7ruwZB1NFl1wwL/CzhvO8Gap3/5cXFlSFp6aXyo2WX/noV
ckVB1Uv0WO6vY5BmRLS2OPvJFMKCpSvaM44vdS5zafX20M3Zx10wEO87rde1TEnk
NRKeaUmvAgMBAAECggEAIFzdu4+8j7zPcuird0IHXj5f48XWMtKQeq+uo8MqDmlX
JpsKDiWB9QydKA0mViP0U8Bi48r50ox3UPHHFdEWRVdyemlaYCYpW4dv2QESb2cM
2khlrTqyOlSG/lXrYkk2jWrvtkrY/byJ2I2ZRUxLXdnOKe4iy3ZSW4aslruNy21N
otRNQrlHI9/QGddJ6Hq3L+UhDmOLUDK8tglpkzvnmhJdtceuimcWAQVmeUtUo4uy
HbFX3VSZsY5PF67hKczOOexQY4Ctryo1tAN5h2jp4QWDKFrFXQdt13rJb0nYCuKi
nlHvo9ISkYiC+0N2c9wkLlAPSMsr19ELbbtAD79QeZQKBgQDyxvaGhvxjOVblg8ji
ubqVivQTw878wQtrnmlIiLG6hMrvri5F5sUSmBbIoZLX+jdVYHjFtOlvwmr7Xo8B
/hx3ECVZJf1dNVJk3Az/ZNdVPPYBpE9NxFT0zAggjdZAKX40l279ejIWE3HHe90N
+HPBOEKbRcOyKtQHOafq5WOiXQKBgQDTaREMIHgyknJcgOtUgadfEtkPHtRHIE+z
Md10dC+ZUXV3U7EZYy9I5NXfoJfZ3hgteIz12YqMQLgyCQeIMj1AZpZf1SD39DJx
x+7bV0Omj9fqwGj147HqZRFMbwtFdRT5e/iabQE4GP1p+8x/llMjfpkrS4YUqyvs
VMtit1zzewKBgHwe4LcSmEKadCTPZYsU7aG68uKP/2kVwSL6UFV3HXaAocg8QwgV
3beN7kgQ4yRslpGdyuE5hwdOXKe7Rl38bs0ogg+77ncS5dcO8c443iaEDjn0qV7W
+6BUF+uc2GbhT9bPfT02lhjXRBp65x9XYMbuXo9H8a9LWi9/eKwNLw05AoGAaA71
JyTsROg0hjemncfbnD5ovLqN/hx3XlqTCHkP3MVtrjhxmW9qnNSWOSaQ19oryGXn
7DMRsQtCHs62+GDSKVrVdYIwYhu+oKaqeSgw0lFHE/N1NmLG9fqdUyPtRljk5BAT
Q9+XlAco5PvdoodZkMUFm3vnGVFPo1nxajua8vUCgYA/xtGIQ3VwgXAeXByYgN/J
Fesm2mw8Xs606NfjEu966lJD5H5FlPWlOyLxj+qxvueQuTTYCDKHfIa05X0PKy4O
PnaN9png/E2m84Y9hbdl+lfAhtjJoQGOMQcfKdtnLPk4/Zf59CLemxZaGAi2ZvFz
08gnXFAov8/njce66VdqzA==
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