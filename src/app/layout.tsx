import { NextAbstractWalletProvider } from "@/components/agw-provider";
import { Toaster } from "@/components/ui/sonner";
import "./globals.css";

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html lang="en">
      <NextAbstractWalletProvider>
        <body>
          {children}
          <Toaster />
        </body>
      </NextAbstractWalletProvider>
    </html>
  );
}
