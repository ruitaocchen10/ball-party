export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[]

export type Database = {
  // Allows to automatically instantiate createClient with right options
  // instead of createClient<Database, { PostgrestVersion: 'XX' }>(URL, KEY)
  __InternalSupabase: {
    PostgrestVersion: "14.15"
  }
  public: {
    Tables: {
      lobbies: {
        Row: {
          closed_at: string | null
          code: string
          created_at: string
          host_id: string
          id: string
        }
        Insert: {
          closed_at?: string | null
          code: string
          created_at?: string
          host_id: string
          id?: string
        }
        Update: {
          closed_at?: string | null
          code?: string
          created_at?: string
          host_id?: string
          id?: string
        }
        Relationships: [
          {
            foreignKeyName: "lobbies_host_id_fkey"
            columns: ["host_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      lobby_members: {
        Row: {
          joined_at: string
          left_at: string | null
          lobby_id: string
          user_id: string
        }
        Insert: {
          joined_at?: string
          left_at?: string | null
          lobby_id: string
          user_id: string
        }
        Update: {
          joined_at?: string
          left_at?: string | null
          lobby_id?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "lobby_members_lobby_id_fkey"
            columns: ["lobby_id"]
            isOneToOne: false
            referencedRelation: "lobbies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "lobby_members_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      match_players: {
        Row: {
          match_id: string
          placement: number | null
          points_awarded: number | null
          raw_score: number | null
          run_id: string
          team: number | null
          user_id: string
        }
        Insert: {
          match_id: string
          placement?: number | null
          points_awarded?: number | null
          raw_score?: number | null
          run_id: string
          team?: number | null
          user_id: string
        }
        Update: {
          match_id?: string
          placement?: number | null
          points_awarded?: number | null
          raw_score?: number | null
          run_id?: string
          team?: number | null
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "match_players_match_id_fkey"
            columns: ["match_id"]
            isOneToOne: false
            referencedRelation: "matches"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "match_players_run_id_user_id_fkey"
            columns: ["run_id", "user_id"]
            isOneToOne: false
            referencedRelation: "run_participants"
            referencedColumns: ["run_id", "user_id"]
          },
        ]
      }
      matches: {
        Row: {
          ended_at: string | null
          game: string
          id: string
          run_id: string
          seq: number
          started_at: string | null
          status: Database["public"]["Enums"]["match_status"]
        }
        Insert: {
          ended_at?: string | null
          game: string
          id?: string
          run_id: string
          seq: number
          started_at?: string | null
          status?: Database["public"]["Enums"]["match_status"]
        }
        Update: {
          ended_at?: string | null
          game?: string
          id?: string
          run_id?: string
          seq?: number
          started_at?: string | null
          status?: Database["public"]["Enums"]["match_status"]
        }
        Relationships: [
          {
            foreignKeyName: "matches_run_id_fkey"
            columns: ["run_id"]
            isOneToOne: false
            referencedRelation: "runs"
            referencedColumns: ["id"]
          },
        ]
      }
      profiles: {
        Row: {
          avatar_url: string | null
          created_at: string
          display_name: string
          id: string
          updated_at: string
        }
        Insert: {
          avatar_url?: string | null
          created_at?: string
          display_name: string
          id: string
          updated_at?: string
        }
        Update: {
          avatar_url?: string | null
          created_at?: string
          display_name?: string
          id?: string
          updated_at?: string
        }
        Relationships: []
      }
      run_participants: {
        Row: {
          run_id: string
          score: number
          seat: number
          user_id: string
        }
        Insert: {
          run_id: string
          score?: number
          seat: number
          user_id: string
        }
        Update: {
          run_id?: string
          score?: number
          seat?: number
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "run_participants_run_id_fkey"
            columns: ["run_id"]
            isOneToOne: false
            referencedRelation: "runs"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "run_participants_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      runs: {
        Row: {
          ended_at: string | null
          id: string
          lobby_id: string
          mode: Database["public"]["Enums"]["run_mode"]
          started_at: string
          status: Database["public"]["Enums"]["run_status"]
          target_score: number | null
        }
        Insert: {
          ended_at?: string | null
          id?: string
          lobby_id: string
          mode: Database["public"]["Enums"]["run_mode"]
          started_at?: string
          status?: Database["public"]["Enums"]["run_status"]
          target_score?: number | null
        }
        Update: {
          ended_at?: string | null
          id?: string
          lobby_id?: string
          mode?: Database["public"]["Enums"]["run_mode"]
          started_at?: string
          status?: Database["public"]["Enums"]["run_status"]
          target_score?: number | null
        }
        Relationships: [
          {
            foreignKeyName: "runs_lobby_id_fkey"
            columns: ["lobby_id"]
            isOneToOne: false
            referencedRelation: "lobbies"
            referencedColumns: ["id"]
          },
        ]
      }
    }
    Views: {
      [_ in never]: never
    }
    Functions: {
      close_lobby: { Args: { p_lobby_id: string }; Returns: undefined }
      create_lobby: {
        Args: never
        Returns: {
          closed_at: string | null
          code: string
          created_at: string
          host_id: string
          id: string
        }
        SetofOptions: {
          from: "*"
          to: "lobbies"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      join_lobby: {
        Args: { p_code: string }
        Returns: {
          closed_at: string | null
          code: string
          created_at: string
          host_id: string
          id: string
        }
        SetofOptions: {
          from: "*"
          to: "lobbies"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      leave_lobby: { Args: { p_lobby_id: string }; Returns: undefined }
    }
    Enums: {
      match_status: "setup" | "playing" | "complete" | "abandoned"
      run_mode: "arcade" | "party"
      run_status: "active" | "finished" | "abandoned"
    }
    CompositeTypes: {
      [_ in never]: never
    }
  }
}

type DatabaseWithoutInternals = Omit<Database, "__InternalSupabase">

type DefaultSchema = DatabaseWithoutInternals[Extract<keyof Database, "public">]

export type Tables<
  DefaultSchemaTableNameOrOptions extends
    | keyof (DefaultSchema["Tables"] & DefaultSchema["Views"])
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
        DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
      DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])[TableName] extends {
      Row: infer R
    }
    ? R
    : never
  : DefaultSchemaTableNameOrOptions extends keyof (DefaultSchema["Tables"] &
        DefaultSchema["Views"])
    ? (DefaultSchema["Tables"] &
        DefaultSchema["Views"])[DefaultSchemaTableNameOrOptions] extends {
        Row: infer R
      }
      ? R
      : never
    : never

export type TablesInsert<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Insert: infer I
    }
    ? I
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Insert: infer I
      }
      ? I
      : never
    : never

export type TablesUpdate<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Update: infer U
    }
    ? U
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Update: infer U
      }
      ? U
      : never
    : never

export type Enums<
  DefaultSchemaEnumNameOrOptions extends
    | keyof DefaultSchema["Enums"]
    | { schema: keyof DatabaseWithoutInternals },
  EnumName extends DefaultSchemaEnumNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"]
    : never = never,
> = DefaultSchemaEnumNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"][EnumName]
  : DefaultSchemaEnumNameOrOptions extends keyof DefaultSchema["Enums"]
    ? DefaultSchema["Enums"][DefaultSchemaEnumNameOrOptions]
    : never

export type CompositeTypes<
  PublicCompositeTypeNameOrOptions extends
    | keyof DefaultSchema["CompositeTypes"]
    | { schema: keyof DatabaseWithoutInternals },
  CompositeTypeName extends PublicCompositeTypeNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"]
    : never = never,
> = PublicCompositeTypeNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"][CompositeTypeName]
  : PublicCompositeTypeNameOrOptions extends keyof DefaultSchema["CompositeTypes"]
    ? DefaultSchema["CompositeTypes"][PublicCompositeTypeNameOrOptions]
    : never

export const Constants = {
  public: {
    Enums: {
      match_status: ["setup", "playing", "complete", "abandoned"],
      run_mode: ["arcade", "party"],
      run_status: ["active", "finished", "abandoned"],
    },
  },
} as const
