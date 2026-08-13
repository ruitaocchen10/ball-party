export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[]

export type Database = {
  graphql_public: {
    Tables: {
      [_ in never]: never
    }
    Views: {
      [_ in never]: never
    }
    Functions: {
      graphql: {
        Args: {
          extensions?: Json
          operationName?: string
          query?: string
          variables?: Json
        }
        Returns: Json
      }
    }
    Enums: {
      [_ in never]: never
    }
    CompositeTypes: {
      [_ in never]: never
    }
  }
  public: {
    Tables: {
      auction_bids: {
        Row: {
          action: string
          automatic: boolean
          bid_seq: number
          by_timeout: boolean
          created_at: string
          match_id: string
          price: number | null
          seq: number
          user_id: string
        }
        Insert: {
          action: string
          automatic?: boolean
          bid_seq: number
          by_timeout?: boolean
          created_at?: string
          match_id: string
          price?: number | null
          seq: number
          user_id: string
        }
        Update: {
          action?: string
          automatic?: boolean
          bid_seq?: number
          by_timeout?: boolean
          created_at?: string
          match_id?: string
          price?: number | null
          seq?: number
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "auction_bids_match_id_seq_fkey"
            columns: ["match_id", "seq"]
            isOneToOne: false
            referencedRelation: "auction_lots"
            referencedColumns: ["match_id", "seq"]
          },
          {
            foreignKeyName: "auction_bids_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      auction_lots: {
        Row: {
          display_name: string
          headshot_url: string | null
          is_flex: boolean
          match_id: string
          opponent: string | null
          player_id: string
          points: number | null
          position: string
          price: number | null
          resolved_at: string | null
          season: number
          seq: number
          slot: string | null
          team: string
          week: number | null
          winner_id: string | null
        }
        Insert: {
          display_name: string
          headshot_url?: string | null
          is_flex: boolean
          match_id: string
          opponent?: string | null
          player_id: string
          points?: number | null
          position: string
          price?: number | null
          resolved_at?: string | null
          season: number
          seq: number
          slot?: string | null
          team: string
          week?: number | null
          winner_id?: string | null
        }
        Update: {
          display_name?: string
          headshot_url?: string | null
          is_flex?: boolean
          match_id?: string
          opponent?: string | null
          player_id?: string
          points?: number | null
          position?: string
          price?: number | null
          resolved_at?: string | null
          season?: number
          seq?: number
          slot?: string | null
          team?: string
          week?: number | null
          winner_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "auction_lots_match_id_fkey"
            columns: ["match_id"]
            isOneToOne: false
            referencedRelation: "matches"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "auction_lots_winner_id_fkey"
            columns: ["winner_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      auction_matches: {
        Row: {
          current_lot: number
          flex_slots: number | null
          lot_count: number
          match_id: string
          opener_seat: number
          phase: string
          phase_deadline: string | null
          purse: number | null
          qb_slots: number | null
          rb_slots: number | null
          roster_preset: string | null
          scoring_mode: string | null
          te_slots: number | null
          turn_deadline: string | null
          turn_seat: number | null
          wr_slots: number | null
        }
        Insert: {
          current_lot?: number
          flex_slots?: number | null
          lot_count: number
          match_id: string
          opener_seat?: number
          phase?: string
          phase_deadline?: string | null
          purse?: number | null
          qb_slots?: number | null
          rb_slots?: number | null
          roster_preset?: string | null
          scoring_mode?: string | null
          te_slots?: number | null
          turn_deadline?: string | null
          turn_seat?: number | null
          wr_slots?: number | null
        }
        Update: {
          current_lot?: number
          flex_slots?: number | null
          lot_count?: number
          match_id?: string
          opener_seat?: number
          phase?: string
          phase_deadline?: string | null
          purse?: number | null
          qb_slots?: number | null
          rb_slots?: number | null
          roster_preset?: string | null
          scoring_mode?: string | null
          te_slots?: number | null
          turn_deadline?: string | null
          turn_seat?: number | null
          wr_slots?: number | null
        }
        Relationships: [
          {
            foreignKeyName: "auction_matches_match_id_fkey"
            columns: ["match_id"]
            isOneToOne: true
            referencedRelation: "matches"
            referencedColumns: ["id"]
          },
        ]
      }
      post_game_actions: {
        Row: {
          choice: Database["public"]["Enums"]["post_game_choice"]
          chosen_at: string
          match_id: string
          next_match_id: string | null
        }
        Insert: {
          choice: Database["public"]["Enums"]["post_game_choice"]
          chosen_at?: string
          match_id: string
          next_match_id?: string | null
        }
        Update: {
          choice?: Database["public"]["Enums"]["post_game_choice"]
          chosen_at?: string
          match_id?: string
          next_match_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "post_game_actions_match_id_fkey"
            columns: ["match_id"]
            isOneToOne: true
            referencedRelation: "matches"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "post_game_actions_next_match_id_fkey"
            columns: ["next_match_id"]
            isOneToOne: false
            referencedRelation: "matches"
            referencedColumns: ["id"]
          },
        ]
      }
      auction_players: {
        Row: {
          budget: number
          match_id: string
          seat: number
          user_id: string
        }
        Insert: {
          budget?: number
          match_id: string
          seat: number
          user_id: string
        }
        Update: {
          budget?: number
          match_id?: string
          seat?: number
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "auction_players_match_id_fkey"
            columns: ["match_id"]
            isOneToOne: false
            referencedRelation: "matches"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "auction_players_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      guest_account_collisions: {
        Row: {
          account_id: string | null
          claim_nonce: string | null
          claimed_at: string | null
          created_at: string
          guest_id: string
        }
        Insert: {
          account_id?: string | null
          claim_nonce?: string | null
          claimed_at?: string | null
          created_at?: string
          guest_id: string
        }
        Update: {
          account_id?: string | null
          claim_nonce?: string | null
          claimed_at?: string | null
          created_at?: string
          guest_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "guest_account_collisions_account_id_fkey"
            columns: ["account_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "guest_account_collisions_guest_id_fkey"
            columns: ["guest_id"]
            isOneToOne: true
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
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
          is_guest: boolean
          updated_at: string
        }
        Insert: {
          avatar_url?: string | null
          created_at?: string
          display_name: string
          id: string
          is_guest?: boolean
          updated_at?: string
        }
        Update: {
          avatar_url?: string | null
          created_at?: string
          display_name?: string
          id?: string
          is_guest?: boolean
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
      auction_state: {
        Args: { p_match_id: string }
        Returns: Database["public"]["CompositeTypes"]["auction_turn"]
        SetofOptions: {
          from: "*"
          to: "auction_turn"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      claim_guest_identity: { Args: never; Returns: string }
      choose_post_game: {
        Args: {
          p_choice: Database["public"]["Enums"]["post_game_choice"]
          p_match_id: string
        }
        Returns: {
          choice: Database["public"]["Enums"]["post_game_choice"]
          chosen_at: string
          match_id: string
          next_match_id: string | null
        }
        SetofOptions: {
          from: "*"
          to: "post_game_actions"
          isOneToOne: true
          isSetofReturn: false
        }
      }
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
      expire_turn: {
        Args: { p_match_id: string }
        Returns: Database["public"]["CompositeTypes"]["auction_turn"]
        SetofOptions: {
          from: "*"
          to: "auction_turn"
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
      pass_lot: {
        Args: { p_match_id: string }
        Returns: Database["public"]["CompositeTypes"]["auction_turn"]
        SetofOptions: {
          from: "*"
          to: "auction_turn"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      place_bid: {
        Args: { p_amount: number; p_match_id: string }
        Returns: Database["public"]["CompositeTypes"]["auction_turn"]
        SetofOptions: {
          from: "*"
          to: "auction_turn"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      record_guest_account_collision: {
        Args: { p_nonce: string }
        Returns: undefined
      }
      start_auction: {
        Args: {
          p_match_id: string
          p_roster_preset: string
          p_scoring_mode: string
        }
        Returns: Database["public"]["CompositeTypes"]["auction_turn"]
        SetofOptions: {
          from: "*"
          to: "auction_turn"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      start_run: {
        Args: {
          p_game: string
          p_lobby_id: string
          p_mode: Database["public"]["Enums"]["run_mode"]
        }
        Returns: {
          ended_at: string | null
          game: string
          id: string
          run_id: string
          seq: number
          started_at: string | null
          status: Database["public"]["Enums"]["match_status"]
        }
        SetofOptions: {
          from: "*"
          to: "matches"
          isOneToOne: true
          isSetofReturn: false
        }
      }
    }
    Enums: {
      match_status: "setup" | "playing" | "complete" | "abandoned"
      post_game_choice: "replay" | "lobby"
      run_mode: "arcade" | "party"
      run_status: "active" | "finished" | "abandoned"
    }
    CompositeTypes: {
      auction_turn: {
        match_id: string | null
        lot_count: number | null
        current_lot: number | null
        turn_seat: number | null
        opener_seat: number | null
        turn_deadline: string | null
        server_now: string | null
        phase: string | null
        phase_deadline: string | null
      }
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
  graphql_public: {
    Enums: {},
  },
  public: {
    Enums: {
      match_status: ["setup", "playing", "complete", "abandoned"],
      run_mode: ["arcade", "party"],
      run_status: ["active", "finished", "abandoned"],
    },
  },
} as const
